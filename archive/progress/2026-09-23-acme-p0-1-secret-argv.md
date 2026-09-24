# P0-1：DNS 凭据命令行与失败输出边界修复

日期：2026-09-23。起始 HEAD：`025d3273d76b58d1cc2a5aa1531ead5025421b98`。
范围：本地 `AcmeConfig/` 实现、单测和一次性 VM 的 `runuser` 语义检查；未使用真实
DNS Token、域名或 ACME CA，未推送或发布。

## 发现与修复

原 `run_as_acme` 将 `load_dns_environment` 的 `KEY=value` 直接放入
`runuser ... env -i KEY=value acme.sh` 的 argv。DNS 签发失败时，顶层异常处理还把
完整 `exc.cmd` 打印到 stderr。因而一个真实 Token 可同时暴露在进程参数和错误日志中。

现在由 Python 的 `subprocess.run(..., env=...)` 设置最小子进程环境，调用
`runuser --user acme --preserve-environment -- acme.sh`。环境覆盖再次在执行边界验证，
`HOME`、`PATH`、`USER`、`LOGNAME` 等身份和执行变量不得来自 DNS 配置。
DNS 签发标准输出/错误由管理器捕获；外部命令失败只输出退出码和受限日志排查提示，
不再回显命令或其携带的数据。

## 本地回归

```bash
python3 AcmeConfig/tests/test_acme_manager.py
/private/tmp/devopstoolkit-p03-runtime-check/bin/ruff check \
  AcmeConfig/libexec/acme-manager AcmeConfig/tests/test_acme_manager.py
PATH=/private/tmp/devopstoolkit-p03-managed/runtime/ansible-core-2.21.4/bin:$PATH \
  ANSIBLE_COLLECTIONS_PATH=/private/tmp/devopstoolkit-p14.hcJpFA/collections \
  ANSIBLE_LOCAL_TEMP=/private/tmp/devopstoolkit-acme-env-verify \
  ./tests/verify-ansible.sh
git diff --check
```

23 项 ACME 单测、Ruff、完整静态门禁及空白检查通过。新增单测断言合成 Token 只在
`subprocess.run` 的 `env` 中、不在 argv；宿主机环境不被意外透传；DNS 签发启用输出
捕获；即使外部异常携带模拟 secret，错误信息也不回显。

## Ubuntu 22.04 一次性 VM

实例 `devopstoolkit-acme-env-test-20260923212000`，Ubuntu 22.04.5 LTS，镜像 hash
`ab5fcc80611a98bf999018045119d87b3a0e7c78f3b43b254b93d5c22bae3ff6`。
只使用合成值 `CF_Token=synthetic-only`，运行：

```bash
multipass exec devopstoolkit-acme-env-test-20260923212000 -- sudo \
  env -i HOME=/home/ubuntu PATH=/usr/bin:/bin USER=ubuntu LOGNAME=ubuntu \
  CF_Token=synthetic-only /usr/sbin/runuser --user ubuntu \
  --preserve-environment -- /bin/sh -c \
  'test "$(id -un)" = ubuntu && test "$HOME" = /home/ubuntu && \
   test "$CF_Token" = synthetic-only && \
   printf "runuser_env_preserved=ok uid=%s\n" "$(id -u)"'
```

输出 `runuser_env_preserved=ok uid=1000`，确认目标系统的 `runuser`
可将受控环境交给非特权用户。**这不是完整 acme-manager 或 provider VM E2E**；
该命令的测试值故意可见于测试 argv，真实凭据从未用于 VM。
完成后按精确名称执行 `multipass stop --force` 与 `multipass delete --purge`；
`multipass list --format json` 返回空列表。VM 与合成数据不可恢复。

## 尚未证明

acme.sh 自身写入的 DNS provider 响应、持久化账户配置及受限日志仍需真实 provider
场景逐项审计；还需真实 CA 首次签发、续期、Ubuntu 22.04 全流程与真实消费者恢复。
本轮修复只关闭了已证实的 argv/错误输出泄漏，不关闭 P0-1。
