local UpdateService = require "UpdateService"

-- LrHttp must run inside an async task.
UpdateService.runCheckFromUi()
