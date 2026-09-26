# P1-2：真实 apt 成功但命令缺失的 VM 验收

受测代码：干净 `main@ff6d3d42595edc5db060c82176e49246d22e7de7`。
环境：一次性 `devops-toolkit-2204-test-20260926-recheck`，Ubuntu 22.04.5
aarch64，镜像 SHA256 `ab5fcc80611a98bf999018045119d87b3a0e7c78f3b43b254b93d5c22bae3ff6`。
使用宿主既有 ansible-core 2.21.4 和锁定 collections，未在宿主安装软件。

在已获授权的 VM 内安装 zsh（APT 临时代理 `192.168.252.1:7897`），备份
`/usr/bin/zsh` 后将原文件移至不在 PATH 的同目录路径。包数据库仍记录 zsh 已安装。
使用 ubuntu 普通账号及 VM 自带 sudo 设置，未增加 sudoers 或免密权限。
SSH Ed25519 指纹经 VM 内与网络扫描交叉核对；保持主机密钥检查。

执行未经替换的 `ansible/playbooks/user-only.yml`，启用
`user_only_allow_system_dependencies=true`、`configure_shell=true`，关闭
Oh My Zsh、Git 配置、uv、Node、Go 和 Linuxbrew。真实 apt 任务输出
`ok`，随后命令重检发现 zsh 缺失，最终断言报告
`Missing commands after dependency convergence: zsh`，退出码 2。
汇总 `ok=12 changed=0 unreachable=0 failed=1`，未执行 user_profile role。

执行前后对 `/home/ubuntu` 所有普通文件排序后的 SHA256 列表作 diff，退出 0，
内容未改变。这不证明目录元数据不变；Ansible 连接产生临时运行文件属于预期行为。
原 zsh 与备份 cmp 相同，已恢复。现有清理脚本因本次非数字后缀拒绝清理，
未修改清理保护；核对精确实例后使用 `multipass delete --purge` 删除该 VM，
随后 `multipass list --format json` 为空。VM 数据不可恢复。

该证据补齐一次性 VM 的真实 apt 故障负例，不是 Ubuntu 24.04 同场景覆盖、
双版本全组件收敛、amd64 验收或正式 Release 的同 SHA 完整 VM 报告。
