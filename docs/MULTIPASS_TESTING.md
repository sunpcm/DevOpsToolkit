# Multipass 真实环境测试

`tests/multipass-smoke.sh` 用一次性 Ubuntu 22.04 和 24.04 实例验证统一 Ansible 实现。

## 为什么必须使用临时实例

Multipass 的 `exec`、`mount` 和常规停止操作依赖虚拟机中的 SSH 22 端口。测试会将 SSH 切换到
`MANAGED_SSH_PORT`（默认 2222），因此切换后 Multipass 可能把仍可通过 2222 正常访问的实例显示为
`Starting` 或不可达。

脚本因此拒绝在非 `*-test-*` 实例上执行端口切换。端口切换后的验证改用目标用户 SSH，清理时只允许
只删除脚本生成的严格命名实例，并先强制停止这些临时实例；不运行全局 `multipass purge`。

## Ubuntu 24.04 的 SSH 端口由 ssh.socket 决定

Ubuntu 22.10 及以后（含 24.04 LTS）默认用 systemd socket 激活 OpenSSH：监听端口由 `ssh.socket`
的 `ListenStream=` 决定，`sshd_config` 里的 `Port` 会被忽略。因此 `ssh_security` 角色会检测 socket
激活，并写入 `/etc/systemd/system/ssh.socket.d/99-devops-toolkit.conf` 来收敛端口；22.04 等传统
`ssh.service` 系统不受影响。

若这一步缺失，24.04 上改端口不会生效，叠加 UFW 只放行新端口，会把主机锁死——这正是本测试覆盖
24.04 的原因。切端口后请始终用目标用户 SSH 到 `MANAGED_SSH_PORT` 验证，`multipass exec` 依赖 22 端口，
切换后会超时属预期。UFW 通过托管应用 profile 收敛，`ufw status` 只显示 profile 名，断言端口请用
`ufw app info DevOpsToolkit`。

## 运行

宿主机需要已经具备 Multipass、Python 3.12–3.14、隔离的 ansible-core 2.21.4、SSH，
以及仓库声明的 Ansible collections。
脚本不会安装这些宿主机依赖。

```bash
./tests/multipass-smoke.sh run
```

默认行为：

- 创建 `devops-toolkit-2204-test-*` 和 `devops-toolkit-2404-test-*`；
- 验证实例版本、Apple Silicon 架构、联网和宿主项目标记文件传输；
- 生成一次性 SSH 密钥并配置 root bootstrap 入口；
- 创建 `devops_test`；prepare 保留 22/2222，随后从普通用户 2222 独立连接执行 finalize，
  最后验证 listener/UFW 已移除 22；
- 安装并检查 Docker 和 Nginx；
- 第二次执行必须满足 `changed=0`、`unreachable=0`、`failed=0`；
- 成功或失败都自动清理脚本创建的临时实例、SSH ControlPath、一次性私钥和工作目录；清理失败会让测试失败。

生成不含凭据的机器可读报告：

```bash
./tests/multipass-smoke.sh run --with-faults \
  --report /tmp/devops-toolkit-vm-smoke.txt
```

报告记录 source SHA、工作树状态、ansible-core 版本、Ubuntu 镜像、故障测试开关、结果和清理状态。
默认即使测试失败也会写报告；报告可保存，一次性私钥和详细临时日志不会被保留。

只有明确需要人工排障时才保留现场：

```bash
./tests/multipass-smoke.sh run --keep
```

`--keep` 会保留一次性私钥和工作目录，且报告中的 `cleanup_status` 为 `skipped-by-request`，不能作为
Release 证据。排障结束后应立即运行文末的严格命名清理命令并删除输出的工作目录。

额外验证 uv 固定产物下载、SHA256 校验和安装：

```bash
./tests/multipass-smoke.sh run --with-uv
```

验证受控 uv 镜像入口：

```bash
DEVOPS_TOOLKIT_UV_RELEASE_BASE_URL="https://可信镜像.example/astral-sh/uv/releases/download/0.9.18" \
  ./tests/multipass-smoke.sh run --with-uv
```

镜像目录必须包含仓库当前 `uv_artifacts` 对应的文件；下载后仍执行固定 SHA256 校验。

如果 Mac 使用仅监听本机的代理，且 Multipass VM 受到 Fake-IP DNS 影响，可以先通过临时 TCP 转发
向 VM 暴露一个无认证的 HTTP 代理，再执行：

```bash
MULTIPASS_TEST_PROXY="http://192.168.252.1:7898" \
  ./tests/multipass-smoke.sh run --with-uv
```

该变量只会在一次性 VM 中写入测试用 `/etc/environment` 和 apt 配置，不会修改宿主机代理配置。
脚本会把 Ansible SSH ControlPath 放在短路径的测试专用临时目录，避免 macOS Unix socket 路径超限。代理
只能使用不含凭据的 `http://host:port`；测试结束后实例会被删除。

在一次性实例中额外执行系统故障注入：

```bash
./tests/multipass-smoke.sh run --with-faults
```

该模式验证无效 sshd 配置在重启前失败、新端口占用时 fail closed、陈旧 UFW profile 在启用默认拒绝前原地收敛、旧 Docker `.list`
源在任何 apt 操作前移除，以及账户创建完成后发生受控中断时，完整重跑和第二次执行仍能达到
`changed=0`。故障模式不会在非 `*-test-*` 实例上切换 SSH 端口；不要把这组测试手工复制到长期服务器。

`--with-uv` 依赖 VM 能稳定访问 GitHub Release assets；默认系统级测试不启用它，避免下载波动掩盖
SSH、UFW、Docker、Nginx 和幂等性结果。`--with-faults` 本身不启用 uv。

只读检查未切换 SSH 端口的实例：

```bash
./tests/multipass-smoke.sh check devops-toolkit-2204 devops-toolkit-2404
```

安全清理脚本生成的临时实例：

```bash
multipass list
./tests/multipass-smoke.sh cleanup \
  devops-toolkit-2204-test-YYYYMMDDhhmmss-PID \
  devops-toolkit-2404-test-YYYYMMDDhhmmss-PID
```

`cleanup` 会拒绝任何不符合临时命名规则的实例。

## CI 与 Release 门禁

GitHub-hosted 容器不能可靠提供 Multipass 所需的硬件虚拟化，不能用容器、syntax check 或 mocked systemd
代替 SSH/UFW/Docker E2E。`.github/workflows/vm-smoke.yml` 因此只在带 `self-hosted` 和 `multipass`
标签的专用可信 runner 上运行：每周六及手工触发，串行执行 Ubuntu 22.04/24.04、二次 `changed=0`
和故障恢复，并在 `always()` 路径复核清理、上传只含元数据的报告。

runner 必须是隔离的测试主机，预装 Multipass、SSH 和 Python 3.12–3.14，允许创建/删除严格命名的
临时 VM；不得与生产工作负载、长期 Multipass 实例或不可信 PR 共用。workflow 会自行创建隔离的
ansible-core 2.21.4 runtime，并按 collection lock 校验依赖。

Release workflow 只接受同一 commit SHA、8 天内成功、`test_faults=1` 且
`cleanup_status=passed` 的 VM smoke artifact。没有安全可用 runner 或没有这份证据时 Release 会
fail closed；维护者必须先在隔离主机手工执行上述报告命令、审阅结果，并完成/接入专用 runner，不能
用静态检查替代后直接发布。
