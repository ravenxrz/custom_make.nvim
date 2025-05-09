-- ~/.config/nvim/lua/custom_make/commands.lua
local M = {}

-- 保存会话状态
local state = {
  flying_make_job_id = nil,
}

-- 导入配置模块
local config = require('custom_make.config')

-- 查找项目根目录
local function find_project_root()
  local output = vim.fn.system('git rev-parse --show-toplevel 2>/dev/null')
  if vim.v.shell_error ~= 0 then
    vim.notify("Not a git repository, using current working directory as root.", vim.log.levels.WARN)
    return vim.fn.getcwd()
  end
  return vim.trim(output)
end

-- 工具函数：获取 Quickfix 窗口 ID
local function get_quickfix_win_id()
  -- 获取所有窗口信息
  local wins = vim.fn.getwininfo()
  local quickfix_win_id = nil
  -- 查找 Quickfix 窗口的 ID
  for _, win in ipairs(wins) do
    if win.quickfix == 1 then
      quickfix_win_id = win.winid
      break
    end
  end
  return quickfix_win_id
end

-- 工具函数：检查 Quickfix 是否为当前活动窗口
local function is_quickfix_active(quickfix_win_id)
  return quickfix_win_id and quickfix_win_id == vim.api.nvim_get_current_win()
end

-- 自动刷新 Quickfix 列表可见范围到最后一行的函数
local function auto_scroll_quickfix(quickfix_win_id)
  if quickfix_win_id then
    -- 获取 Quickfix 列表的总行数
    local line_count = vim.api.nvim_buf_line_count(vim.fn.getwininfo(quickfix_win_id)[1].bufnr)
    -- 设置 Quickfix 窗口的滚动位置到最后一行
    vim.fn.setwinvar(quickfix_win_id, '&scrollbind', 0)
    vim.fn.setwinvar(quickfix_win_id, '&scl', 'yes')
    vim.api.nvim_win_set_cursor(quickfix_win_id, { line_count, 0 })
    vim.fn.setwinvar(quickfix_win_id, '&scrollbind', 1)
  end
end

-- 打开 Quickfix 但保持当前窗口为活动窗口
local function copen_but_remain_cur_win()
  local cur_win = vim.api.nvim_get_current_win()
  vim.cmd('copen')
  vim.api.nvim_set_current_win(cur_win)
end

-- 执行 make 命令的核心函数
local function do_make(opts)
  -- 如果没有提供参数，则尝试从配置文件获取
  if not opts.container_name or not opts.build_dir then
    local cfg = get_or_prompt_config()
    if not cfg then
      return
    end

    opts.container_name = opts.container_name or cfg.container_name
    opts.build_dir = opts.build_dir or cfg.build_dir
    opts.target = opts.target or cfg.target
  end

  local qf_open = false
  -- 构建编译命令
  local docker_command = string.format(
    'docker exec %s bash -c "cd %s; make %s -j"',
    opts.container_name,
    opts.build_dir,
    opts.target or ""
  )

  print(string.format("exec cmd: %s", docker_command))

  -- 清空 quickfix 窗口
  vim.fn.setqflist({}, 'r')
  state.flying_make_job_id = vim.fn.jobstart(docker_command, {
    on_exit = function(_, exit_code)
      state.flying_make_job_id = nil
      local qwinid = get_quickfix_win_id()
      if not qf_open and exit_code == 0 then
        -- 打开 quickfix 窗口
        copen_but_remain_cur_win()
        auto_scroll_quickfix(qwinid)
      else
        if exit_code == 0 then
          vim.cmd("cclose")
        end
      end
      print("compile finished, with exit code", exit_code)
    end,
    -- 当有标准输出时的回调函数
    on_stdout = function(_, data)
      if data then
        -- 将标准输出数据添加到 quickfix 列表
        vim.fn.setqflist({}, 'a', { lines = data })
        if not qf_open then
          copen_but_remain_cur_win()
          qf_open = true
        end
        local qwinid = get_quickfix_win_id()
        if not is_quickfix_active(qwinid) then
          auto_scroll_quickfix(qwinid)
        end
      end
    end,
    -- 当有标准错误输出时的回调函数
    on_stderr = function(_, data)
      if data then
        -- 将标准错误输出数据添加到 quickfix 列表
        vim.fn.setqflist({}, 'a', { lines = data })
        if not qf_open then
          copen_but_remain_cur_win()
          qf_open = true
        end
        local qwinid = get_quickfix_win_id()
        if not is_quickfix_active(qwinid) then
          auto_scroll_quickfix(qwinid)
        end
      end
    end
  })
end

local function get_or_prompt_config(callback)
  -- 检查配置文件是否存在
  if config.config_file_exists() then
    local cfg, err = config.read_config()
    if err then
      vim.notify("Error reading config file: " .. err, vim.log.levels.ERROR)
      callback(nil)
      return
    end

    if cfg.container_name and cfg.build_dir then
      callback(cfg)
      return
    else
      vim.notify("Config file is missing required fields", vim.log.levels.WARN)
    end
  end

  -- 配置文件不存在或不完整，询问用户
  vim.ui.select({ "Create config file", "Enter manually", "Cancel" }, {
    prompt = "No valid config file found. What would you like to do?",
  }, function(choice)
    if not choice or choice == "Cancel" then
      callback(nil)
      return
    end

    if choice == "Create config file" then
      -- 创建配置文件
      vim.ui.input({ prompt = "Docker container name: " }, function(container_name)
        if not container_name or container_name == "" then
          vim.notify("Container name is required", vim.log.levels.ERROR)
          callback(nil)
          return
        end

        vim.ui.input({ prompt = "Build directory: " }, function(build_dir)
          if not build_dir or build_dir == "" then
            vim.notify("Build directory is required", vim.log.levels.ERROR)
            callback(nil)
            return
          end

          -- 转换相对路径为绝对路径
          if build_dir:sub(1, 1) ~= '/' then
            local project_root = find_project_root()
            build_dir = project_root .. '/' .. build_dir
            vim.notify("Converted relative path to: " .. build_dir, vim.log.levels.INFO)
          end

          vim.ui.input({ prompt = "Default build target (optional): " }, function(target)
            local success, err = config.write_config({
              container_name = container_name,
              build_dir = build_dir,
              target = target or ""
            })

            if success then
              vim.notify("Config file created at " .. config.get_config_file_path(), vim.log.levels.INFO)
              callback({
                container_name = container_name,
                build_dir = build_dir,
                target = target or ""
              })
            else
              vim.notify("Failed to create config file: " .. err, vim.log.levels.ERROR)
              callback(nil)
            end
          end)
        end)
      end)
    elseif choice == "Enter manually" then
      -- 手动输入
      vim.ui.input({ prompt = "Docker container name: " }, function(container_name)
        if not container_name or container_name == "" then
          vim.notify("Container name is required", vim.log.levels.ERROR)
          callback(nil)
          return
        end

        vim.ui.input({ prompt = "Build directory: " }, function(build_dir)
          if not build_dir or build_dir == "" then
            vim.notify("Build directory is required", vim.log.levels.ERROR)
            callback(nil)
            return
          end

          -- 转换相对路径为绝对路径
          if build_dir:sub(1, 1) ~= '/' then
            local project_root = find_project_root()
            build_dir = project_root .. '/' .. build_dir
            vim.notify("Converted relative path to: " .. build_dir, vim.log.levels.INFO)
          end

          vim.ui.input({ prompt = "Build target (optional): " }, function(target)
            callback({
              container_name = container_name,
              build_dir = build_dir,
              target = target or ""
            })
          end)
        end)
      end)
    end
  end)
end

-- 提取执行 MakeSelect 逻辑的函数
local function execute_make_select(container_name, root_path)
  local cmd = string.format("docker exec %s bash -c 'cd %s; cmake --build . --target help'", container_name, root_path)
  local output = vim.fn.system(cmd)
  local exit_code = vim.v.shell_error

  if exit_code ~= 0 then
    print(string.format("get targets list failed, exit_code:%d output:%s", exit_code, output))
    vim.notify("Failed to get build targets", vim.log.levels.ERROR)
    return
  end

  -- 解析输出，提取所有的 target
  local targets = {}
  for line in output:gmatch("[^\n]+") do
    local target = line:match("^%s-%.%.%.%s+(%S+)")
    if target then
      table.insert(targets, target)
    end
  end

  if #targets == 0 then
    vim.notify("No build targets found", vim.log.levels.WARN)
    return
  end

  -- 使用 vim.ui.select 供用户选择
  vim.ui.select(targets, {
    prompt = "Choose target",
  }, function(choice)
    if choice then
      do_make({
        container_name = container_name,
        build_dir = root_path,
        target = choice
      })

      -- 更新配置文件中的 target
      get_or_prompt_config(function(cfg)
        if cfg then
          cfg.target = choice
          config.write_config(cfg)
        end
      end)
    end
  end)
end

-- 设置命令
M.setup = function(opts)
  -- 注册 :Make 命令
  vim.api.nvim_create_user_command("Make", function(opts)
    if state.flying_make_job_id and vim.fn.jobwait({ state.flying_make_job_id }, 0)[1] == -1 then
      vim.notify('There is already a job running with ID: ' .. state.flying_make_job_id, vim.log.levels.ERROR)
      return
    end

    -- 设置参数
    local args = vim.split(opts.args, ' ', { trimempty = true })

    -- 如果没有提供参数，尝试从配置文件获取
    if #args == 0 then
      get_or_prompt_config(function(cfg)
        if cfg then
          do_make({
            container_name = cfg.container_name,
            build_dir = cfg.build_dir,
            target = cfg.target or ""
          })
        end
      end)
      return
    end

    -- 处理提供了参数的情况
    local container_name, build_dir, target

    if #args >= 2 then
      container_name = args[1]
      build_dir = args[2]
      target = #args > 2 and table.concat(args, ' ', 3) or ""
    else
      vim.notify('Make command requires at least 2 arguments: container_name and build_dir', vim.log.levels.ERROR)
      return
    end

    -- 处理相对路径
    if build_dir:sub(1, 1) ~= '/' then
      local cwd = vim.fn.getcwd()
      build_dir = cwd .. '/' .. build_dir
    end

    do_make({
      container_name = container_name,
      build_dir = build_dir,
      target = target
    })
  end, {
    nargs = '*'
  })

  -- 注册 :MakeSelect 命令
  vim.api.nvim_create_user_command("MakeSelect", function(opts)
    local container_name
    local root_path

    -- 设置参数
    local args = vim.split(opts.args, ' ', { trimempty = true })

    -- 如果没有提供参数，尝试从配置文件获取
    if #args == 0 then
      get_or_prompt_config(function(cfg)
        if not cfg then
          return
        end

        container_name = cfg.container_name
        root_path = cfg.build_dir
        execute_make_select(container_name, root_path)
      end)
    elseif #args == 2 then
      container_name = args[1]
      root_path = args[2]

      -- 处理相对路径
      if root_path:sub(1, 1) ~= '/' then
        local cwd = vim.fn.getcwd()
        root_path = cwd .. '/' .. root_path
      end
      execute_make_select(container_name, root_path)
    else
      vim.notify('MakeSelect command requires 0 or 2 arguments: container_name and build_dir', vim.log.levels.ERROR)
      return
    end
  end, {
    nargs = '*'
  })

  -- 注册 :KillMake 命令
  vim.api.nvim_create_user_command('KillMake', function(opts)
    if state.flying_make_job_id and vim.fn.jobwait({ state.flying_make_job_id }, 0)[1] == -1 then
      -- 终止 Neovim 作业本身
      vim.fn.jobstop(state.flying_make_job_id)
      vim.notify('Job with ID ' .. state.flying_make_job_id .. ' has been killed', vim.log.levels.INFO)
      state.flying_make_job_id = nil
    end

    -- 终止容器内的编译进程
    local commands_to_kill = {
      "bash -c",
      "ld",
      "cc1plus"
    }

    local container_name = nil

    if opts.args and opts.args ~= "" then
      container_name = opts.args
    else
      -- 尝试从配置文件获取容器名
      local cfg, err = config.read_config()
      if not err and cfg and cfg.container_name then
        container_name = cfg.container_name
      else
        vim.notify("No container name specified or found", vim.log.levels.WARN)
        return
      end
    end

    for _, command in ipairs(commands_to_kill) do
      local kill_command = string.format('docker exec %s pkill -f "%s"', container_name, command)
      print(kill_command)
      vim.fn.system(kill_command)
    end

    vim.cmd('cclose')
  end, {
    nargs = "?",
    -- 命令的描述
    desc = 'Kill the currently running Make job'
  })
end

return M
