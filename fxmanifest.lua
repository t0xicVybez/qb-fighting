fx_version 'cerulean'
game 'gta5'

author 'Ronin Development'
description 'QBCore Fighting System'
version '1.0.0'

shared_scripts {
    '@qb-core/shared/locale.lua',
    'locales/en.lua',
    'config.lua'
}

client_scripts {
    'client/main.lua',
    'client/events.lua',
    'client/functions.lua',
    'client/animations.lua',
    'client/nui.lua'
}

server_scripts {
    '@oxmysql/lib/MySQL.lua',
    'server/main.lua',
    'server/events.lua',
    'server/functions.lua',
    'server/business.lua',
    'server/betting.lua'
}

lua54 'yes'

dependencies {
    'qb-core',
    'oxmysql'
}

files {
    'html/index.html',
    'html/style.css',
    'html/script.js'
}

ui_page 'html/index.html'