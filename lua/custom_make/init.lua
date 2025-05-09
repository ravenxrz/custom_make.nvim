-- ~/.config/nvim/lua/custom_make/init.lua
local M = {}



M.setup = function(opts)
  -- 导入 plenary.path（如果尚未安装，需要先安装）
  local has_plenary, _ = pcall(require, 'plenary.path')
  if not has_plenary then
    error("custom_make.nvim requires nvim-lua/plenary.nvim")
  end

  M.config = vim.tbl_deep_extend("force", {
  }, opts or {})
  require("custom_make.commands").setup(M.config)
end

return M
