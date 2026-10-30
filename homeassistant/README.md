# Home Assistant & Mosquitto MQTT Server (VPS Stack)

Esta pasta contém a stack docker-compose para rodar o **Home Assistant Core** e o **Eclipse Mosquitto (MQTT Broker)** na sua VPS, servindo como o hub de automação e controle remoto da sua estação de trabalho (Lenovo LOQ / Windows 11 + WSL2).

---


> [!TIP]
> Para o procedimento detalhado e o guia de deploy automatizado via SSH / Tailscale com o comando `make ha-vps-deploy`, consulte [VPS_DEPLOY.md](VPS_DEPLOY.md).

## 1. Pré-Requisitos na VPS

1. **Docker e Docker Compose** instalados na VPS.
2. **Tailscale** instalado e autenticado na mesma tailnet do seu PC e smartphone:
   ```bash
   curl -fsSL https://tailscale.com/install.sh | sh
   sudo tailscale up
   ```
3. Anote o IP da VPS no Tailscale (ex: `100.x.y.z` ou via MagicDNS: `vps-nome.sua-tailnet.ts.net`).

---

## 2. Passo a Passo de Instalação na VPS

### Passo 1: Copiar os arquivos para a VPS
Copie esta pasta `homeassistant/` para a VPS (ex: em `/opt/homeassistant` ou `~/homeassistant`):
```bash
rsync -avz ./homeassistant/ usuario@vps-ip:~/homeassistant/
```

### Passo 2: Criar o arquivo de credenciais do Mosquitto
Acesse a pasta na VPS e gere a senha do usuário MQTT (ex: usuário `hass`):
```bash
cd ~/homeassistant
docker compose run --rm mosquitto mosquitto_passwd -c /mosquitto/config/password_file hass
```
*O utilitário solicitará a digitação da senha duas vezes e salvará o hash seguro em `mosquitto/config/password_file`.*

### Passo 3: Criar o `.env`
Copie o template de variáveis de ambiente:
```bash
cp .env.example .env
```
Ajuste o `TZ` caso seu fuso seja diferente de `America/Fortaleza`.

### Passo 4: Subir os Containers
```bash
docker compose up -d
```
Verifique se os containers estão saudáveis:
```bash
docker compose ps
docker compose logs -f
```

---

## 3. Configuração Inicial do Home Assistant

1. Abra o navegador no seu PC ou celular e acesse o endereço do Home Assistant via Tailscale:
   ```
   http://<IP-TAILSCALE-DA-VPS>:8123
   ```
2. Crie sua conta de administrador.
3. Vá em **Configurações (Settings) -> Dispositivos e Serviços (Devices & Services) -> Adicionar Integração**.
4. Procure por **MQTT** e configure com os dados:
   - **Broker**: `127.0.0.1` (ou o IP do Tailscale)
   - **Porta**: `1883`
   - **Usuário**: `hass`
   - **Senha**: A senha definida no Passo 2.
5. Pronto! O Home Assistant agora escuta o broker MQTT com auto-discovery habilitado. Assim que o **HASS.Agent** for iniciado no seu Windows, os sensores e comandos aparecerão automaticamente como entidades no painel.

---

## 4. Configuração no Smartphone (App Oficial)

1. Instale o aplicativo **Tailscale** no seu celular e conecte-se à mesma conta.
2. Instale o app oficial **Home Assistant** (Google Play Store ou Apple App Store).
3. Na primeira inicialização do app, defina a URL do servidor como:
   ```
   http://<IP-TAILSCALE-DA-VPS>:8123
   ```
4. Faça login com suas credenciais.
5. Você terá acesso seguro ao dashboard de controle (botões de desligar, suspender, abrir apps e status do PC) de qualquer lugar do mundo (4G/5G/Wi-Fi externo) através do túnel criptografado do Tailscale.
