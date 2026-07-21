return {
  {
    "danymat/neogen",
    opts = {
      snippet_engine = "luasnip",
      input_after_comment = true, -- Automatically jump into insert mode after generating the comment
      languages = {
        cpp = {
          template = {
            annotation_convention = "doxygen", -- Add this back
            file = {
              template = {
                "/**",
                " * @file ${file_name}",
                " * @brief ${2:Brief description of the file}", -- Added snippet placeholder
                " * @author ${3:Your Name}", -- Added snippet placeholder
                " * @date " .. os.date("%Y-%m-%d") .. "", -- Dynamic date
                " * @copyright Copyright (c) " .. os.date("%Y") .. ", ${4:Your Company/Organization}", -- Dynamic year and snippet placeholder
                " */",
              },
            },
          },
        },
        c = {
          template = {
            annotation_convention = "doxygen", -- Add this back
            file = {
              template = {
                "/**",
                " * @file ${file_name}",
                " * @brief ${2:Brief description of the file}", -- Added snippet placeholder
                " * @author ${3:Your Name}", -- Added snippet placeholder
                " * @date " .. os.date("%Y-%m-%d") .. "", -- Dynamic date
                " * @copyright Copyright (c) " .. os.date("%Y") .. ", ${4:Your Company/Organization}", -- Dynamic year and snippet placeholder
                " */",
              },
            },
          },
        },
      },
    },
    config = true,
    -- Uncomment next line if you want to follow only stable versions
    -- version = "*"
  },
}
