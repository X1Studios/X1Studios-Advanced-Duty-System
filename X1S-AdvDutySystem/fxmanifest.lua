fx_version 'cerulean'
game 'gta5'

author 'X1Studios'
description 'Advanced Standalone Duty System + 911 Call System and Panic System'
version '1.2.0'

ui_page 'html/index.html'

files {
    'html/index.html',
    'html/style.css',
    'html/script.js',
    'html/banner.png',
}

shared_scripts {
    'config.lua'
}

client_scripts {
    'client/client.lua'
}

server_scripts {
    'server/server.lua'
}
