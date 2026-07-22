fx_version 'cerulean'
game 'gta5'

author 'X1Studios'
description 'Advanced Standalone Duty System + 911 Call System and Panic System'
version '1.6.1'

ui_page 'html/index.html'

files {
    'html/index.html',
    'html/style.css',
    'html/script.js',
    'html/banner.png',
    'locales.json',
}

shared_script 'config.lua'

client_scripts {
    'client/client.lua'
}

server_scripts {
    'server_config.lua',
    'server/server.lua'
}
