# P1-4 一次性 VM 首轮实测

日期：2026-09-23

代码提交：`b41a1e648b06f173391d26ab5c6ea6e2a5eed38e`

## 本地门禁

- `./tests/verify-ansible.sh`：通过，包含向导 prepare/finalize 编排、四组 Playbook/role 路径、
  VM 报告负向校验、临时实例清理边界及安装/Release 回归。
- 固定版本 Ruff、Yamllint、ShellCheck、Actionlint、Gitleaks：通过。
- `multipass list --format json`：测试前为空。
- 独立 ansible-core 2.21.4 运行时可用；三份原始 collection 归档通过 lock SHA256 校验，
  安装后的精确集合及版本再次通过校验。

## 真实 VM 执行

命令：

```bash
ANSIBLE_COLLECTIONS_PATH=<经 lock 校验的独立临时目录>/collections \
  uv run --with ansible-core==2.21.4 \
  ./tests/multipass-smoke.sh run --with-faults --report <独立临时目录>/vm-report.txt
```

22.04 与 24.04 两台一次性 VM 均启动成功。22.04 镜像为 Ubuntu 22.04.5 LTS，
镜像 hash `ab5fcc80611a`，架构 `aarch64`；初始网络解析、SSH 服务和项目标记文件传输通过。
首次 Playbook 在 `system_base : Install system profile dependencies` 的 apt cache 更新处失败：
`Failed to update apt cache after 5 retries`。因此 SSH/UFW/Docker/Nginx、第二次 `changed=0`
和故障恢复没有跑到，不能把本次计为 E2E 通过。

报告记录 `result=failed`、`source_dirty=false`、`test_faults=1`、
`cleanup_status=passed`。退出后再次执行 `multipass list --format json`，实例列表为空。

## 发现与后续

首轮报告还暴露了 ansible-core 版本解析末尾带 `]` 的缺陷；已修正解析并增加测试。
宿主机直连 Ubuntu 软件源返回 HTTP 200，但 VM apt 更新失败。后续需在隔离 VM 中进一步确认
软件源、DNS、网络路由或受控代理入口，再重跑完整 22.04/24.04 测试。

随后用独立的一次性 22.04 诊断 VM 确认：其 DNS 把 `ports.ubuntu.com` 返回为
`198.18.0.7` Fake-IP，`apt-get update` 明确报 `Could not connect ... (198.18.0.7)`。
宿主机通过公共 DNS 查询到真实地址后，仅在诊断 VM 的 `/etc/hosts` 临时覆盖
`ports.ubuntu.com`，APT 成功下载约 47.8 MB 索引；同样覆盖 `download.docker.com` 后，
Docker 官方 GPG URL 返回 HTTP 200。诊断 VM 已删除，`multipass list --format json` 再次为空。
这证明首轮阻断是 VM DNS/Fake-IP 路由，而非 Playbook 的 apt 任务逻辑。

测试脚本现支持 `MULTIPASS_TEST_HOSTS`，只接受上述两个官方域名及公网 IPv4，且只写入严格
命名的一次性 VM；映射会写进报告。地址需要在每次运行前重新查询，不用于生产主机。

第二轮完整 smoke 从干净提交 `dcdc5f2` 启动了两台 VM，但在 DNS 覆盖的第一条写入后等待：
`multipass exec ... sudo tee` 的标准输入没有结束，第二条映射未写入。确认阻塞点后发送 SIGINT；
报告为 `result=failed`、`cleanup_status=passed`，实例列表再次为空。测试脚本现改为经过白名单
校验的 `sudo sh -c` 非交互写入，并由本地测试检查两条命令均生成；完整 E2E 仍需重跑。

GitHub 专用 `self-hosted,multipass` runner 尚未接入，计划任务与 Release 同 SHA 门禁还没有远端运行证据。
Release workflow 会在缺少近期同 SHA 成功报告时 fail closed。
