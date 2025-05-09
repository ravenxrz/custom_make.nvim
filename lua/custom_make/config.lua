-- ~/.config/nvim/lua/custom_make/config/init.lua
local M = {}
local Path = require('plenary.path')
local json = vim.json

-- 配置文件名称（隐藏文件）
M.config_file_name = '.custom_make.json'

-- 获取当前项目的配置文件路径
function M.get_config_file_path()
  local cwd = vim.fn.getcwd()
  return Path:new(cwd, M.config_file_name):absolute()
end

-- 检查配置文件是否存在
function M.config_file_exists()
  local config_path = M.get_config_file_path()
  return Path:new(config_path):exists()
end

-- 读取配置文件
function M.read_config()
  local config_path = M.get_config_file_path()
  
  -- 检查文件是否存在
  if not Path:new(config_path):exists() then
    return nil, "Config file not found"
  end
  
  local content = Path:new(config_path):read()
  
  if not content or content == '' then
    return nil, 'Config file is empty'
  end
  
  local ok, config = pcall(function() return json.decode(content) end)
  if not ok then
    return nil, 'Failed to parse config file: ' .. config
  end
  
  return config, nil
end

-- 创建配置文件模板
function M.create_config_template(container_name, build_dir, target)
  local template = {
    container_name = container_name or '',
    build_dir = build_dir or '',
    target = target or ''
  }
  
  return json.encode(template, { indent = 2 })
end

-- 写入配置文件
function M.write_config(config)
  local config_path = M.get_config_file_path()
  local content = json.encode(config, { indent = 2 })
  
  local ok, err = pcall(function()
    Path:new(config_path):write(content, 'w')
  end)
  
  if not ok then
    return false, err
  end
  
  return true, nil
end

-- 打开配置文件进行编辑
function M.edit_config()
  local config_path = M.get_config_file_path()
  vim.cmd('edit ' .. vim.fn.fnameescape(config_path))
end

return M
