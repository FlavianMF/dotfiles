# Procedimento Operacional: Preparação da VPS e Deploy do Home Assistant

Este documento descreve os passos para preparar sua **VPS na nuvem** e executar o **deploy contínuo e automatizado** da stack Home Assistant + Eclipse Mosquitto via Tailscale.

---

## 1. Preparação da VPS (Executar uma única vez na VPS)

Acesse sua VPS via SSH:
```bash
ssh usuario@ip-da-vps
```

### 1.1. Instalar Docker e Docker Compose
```bash
curl -fsSL https://get.docker.com | sh
sudo usermod -aG docker $USER
sudo systemctl enable --now docker
```

### 1.2. Instalar e Ativar o Tailscale
O Tailscale cria uma VPN mesh privada com WireGuard, permitindo comunicação direta e segura com o seu PC e celular sem expor portas na internet:
```bash
curl -fsSL https://tailscale.com/install.sh | sh
sudo tailscale up
tailscale ip -4  # Anote este IP privado (ex: 100.x.y.z)
```

### 1.3. Autorizar Chave SSH Pública (Para Deploy Sem Senha)
Para permitir que o comando local `make ha-vps-deploy` execute automaticamente:
1. No seu WSL2 local, pegue sua chave pública (`cat ~/.ssh/id_flavian_mf_github.pub` ou equivalente).
2. Na VPS, adicione a chave ao arquivo `authorized_keys`:
```bash
mkdir -p ~/.ssh && chmod 700 ~/.ssh
echo "sua-chave-publica-aqui" >> ~/.ssh/authorized_keys
chmod 600 ~/.ssh/authorized_keys
```

### 1.4. Criar Diretório de Destino
```bash
sudo mkdir -p /opt/homeassistant && sudo chown -R $USER:$USER /opt/homeassistant
```

---

## 2. Configuração Local no Repositório (WSL2)

### 2.1. Criar o arquivo `secrets/mqtt.env`
No seu terminal local no WSL2, crie o arquivo de credenciais a partir do template:
```bash
cp secrets/mqtt.env.example secrets/mqtt.env
```
Edite `secrets/mqtt.env` com o IP retornado pelo `tailscale ip -4` na VPS e defina sua senha:
```ini
MQTT_HOST=100.x.y.z
MQTT_PORT=1883
MQTT_USER=hass
MQTT_PASSWORD=sua_senha_segura
```
*(O arquivo `secrets/mqtt.env` é estritamente ignorado pelo git e nunca será commitado).*

---

## 3. Disparo do Deploy Automatizado

No diretório raiz do repositório `dotfiles` no WSL2, execute:
```bash
make ha-vps-deploy VPS=usuario@100.x.y.z
```
*(Ou defina `export VPS_HOST="usuario@100.x.y.z"` no seu shell para rodar apenas `make ha-vps-deploy`).*

### O que o script `bin/ha-deploy` faz automaticamente:
1. Testa a conectividade SSH com a VPS.
2. Sincroniza a pasta `homeassistant/` atualizada via `rsync`.
3. Executa o utilitário `mosquitto_passwd` dentro do container Mosquitto para criar o hash seguro da senha em `mosquitto/config/password_file`.
4. Dispara `docker compose up -d` na VPS.
5. Verifica a saúde dos containers e imprime o link de acesso: `http://100.x.y.z:8123`.

---

## 4. Configuração Pós-Deploy

### 4.1. No Home Assistant (Primeiro Acesso)
1. Acesse `http://<IP-TAILSCALE-VPS>:8123` pelo navegador do PC ou celular.
2. Crie sua conta de administrador.
3. Vá em **Configurações -> Dispositivos e Serviços -> Adicionar Integração -> MQTT**:
   - Broker: `127.0.0.1` (ou o IP do Tailscale)
   - Porta: `1883`
   - Usuário: `hass` (ou o configurado em `secrets/mqtt.env`)
   - Senha: A senha definida em `secrets/mqtt.env`

### 4.2. No Windows 11 Host (HASS.Agent)
Abra o PowerShell como Administrador e execute:
```powershell
.\powershell\hass-agent\install-hass-agent.ps1 -RegisterCommands
```
Abra o HASS.Agent no Menu Iniciar, vá em **Configuration -> MQTT Settings**, aponte para o IP Tailscale da VPS (`100.x.y.z:1883`), informe usuário e senha, e clique em **Store & Activate**.

### 4.3. No Smartphone
1. Conecte-se ao app do Tailscale no celular.
2. Abra o app oficial Home Assistant e aponte para `http://<IP-TAILSCALE-VPS>:8123`.
3. Seus controles de energia, aplicativos e diagnósticos estarão disponíveis na ponta dos dedos!
