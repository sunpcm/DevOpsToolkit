# P0-1：交互式 ACME 子进程日志默认权限

日期：2026-09-23。起始 HEAD：`98ce487e307eb6a26f212bd1da0746349fec1dcc`。
此前 DNS Token 的 argv/错误输出修复见 [`2026-09-23-acme-p0-1-secret-argv.md`](2026-09-23-acme-p0-1-secret-argv.md)。

`acme-renew.service` 已声明 `UMask=0077`，而交互式 `acme-add` 经 Python
`subprocess.run` 启动 acme.sh 时此前继承调用者的 umask。现显式传入 `umask=0o077`，
避免首次创建的受管日志随调用者默认值变成 group/other 可读。单测断言执行边界传入
此值；该断言只覆盖管理器参数，尚未证明 acme.sh 或 logrotate 最终文件模式。

```bash
python3 AcmeConfig/tests/test_acme_manager.py
/private/tmp/devopstoolkit-p03-runtime-check/bin/ruff check \
  AcmeConfig/libexec/acme-manager AcmeConfig/tests/test_acme_manager.py
PATH=/private/tmp/devopstoolkit-p03-managed/runtime/ansible-core-2.21.4/bin:$PATH \
  ANSIBLE_COLLECTIONS_PATH=/private/tmp/devopstoolkit-p14.hcJpFA/collections \
  ANSIBLE_LOCAL_TEMP=/private/tmp/devopstoolkit-acme-log-verify \
  ./tests/verify-ansible.sh
git diff --check
```

结果：23 项 ACME 单测、Ruff、完整 `verify-ansible.sh` 和差异空白检查均通过。

真实 DNS provider 响应、acme.sh 持久化状态、首次日志和轮替/压缩日志的 owner/mode
仍须在受控域名与一次性 VM 中验收；本地默认权限补强不关闭 P0-1。
