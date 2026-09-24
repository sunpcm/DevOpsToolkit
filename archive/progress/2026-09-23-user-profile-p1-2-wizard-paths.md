# P1-2：向导关键开关路径测试

日期：2026-09-23。实现基线：`c07edbddd6a418207a0ba13bde5d0f29817bc141`；本报告和测试修改所在的提交以 Git 历史为准。未更改目标主机、宿主机软件或远端。

`tests/test-wizard.py` 现从 `collect_user_modules` 到 `collect_user_only` 验证：

- 基础 Shell 关闭、Oh My Zsh 被误选时，向导提示并只关闭 Oh My Zsh；uv、Node、Go、共享 Linuxbrew 的选择保持不变。
- Node/Go 版本只在相应组件启用时询问；Git 配置关闭时不询问身份。
- user-only 的系统依赖安装例外默认禁止；只有显式确认后，变量为 true 并增加 `--ask-become-pass`。

已有测试继续覆盖远程已有账户与仅密钥新账户。执行：

```bash
python3 tests/test-wizard.py
PATH=/private/tmp/devopstoolkit-p03-managed/runtime/ansible-core-2.21.4/bin:$PATH \
  ANSIBLE_COLLECTIONS_PATH=/private/tmp/devopstoolkit-p14.hcJpFA/collections \
  ANSIBLE_LOCAL_TEMP=/private/tmp/devopstoolkit-p1-2-wizard-verify \
  ./tests/verify-ansible.sh
git diff --check
```

上述向导测试、完整静态门禁和差异空白检查通过。此结果不证明真实 VM 的语言工具安装、登录 Shell 加载或所有组合二次 `changed=0`；P1-2 继续开放。
