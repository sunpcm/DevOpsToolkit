# VM 报告镜像与实例一致性补强

日期：2026-09-24。适用范围：草稿 PR #2 的 `tests/multipass-smoke.sh`、
`scripts/verify-vm-evidence.py` 与对应本地测试。修改前基线为
`dabb492713050f5702043a6e4684340d54a09604`；最终提交以 PR head 与 CI 的 SHA 为准。

## 发现与改动

原 smoke 报告固定写入 `ubuntu_images=22.04,24.04`，但执行路径没有明确验证
临时实例中的 `/etc/os-release` 与实例名对应；报告校验器也未核对 `instances`。
现在每个实例在配置前必须证明 Ubuntu ID 与预期 `VERSION_ID`，否则测试失败；
审批前校验要求一对同一次运行的 22.04/24.04 临时实例名。

这只提高本地报告的内部一致性。报告是本地文本，不能独立证明运行主机、镜像来源
或内容未被伪造。发布审批人仍须保留原件和 SHA256，核对当次候选 SHA，且实际运行
默认双 VM 命令；不能把定向单元测试当作真实 VM 证据。

## 本地复现

在仓库根目录：

```bash
python3 tests/test-vm-evidence.py
./tests/test-multipass-report.sh
shellcheck tests/multipass-smoke.sh tests/test-multipass-report.sh
PATH="/opt/homebrew/Cellar/ansible/14.2.0_1/libexec/bin:$PATH" ./tests/verify-ansible.sh
git diff --check
```

结果：定向正反例、ShellCheck、完整 `verify-ansible.sh` 与 diff 检查通过。
完整验证首次在受限沙箱中被已安装 Ansible 的本地 RPC 启动限制打断，
随后在允许该 RPC 的环境使用同一已安装版本重跑通过；没有安装新依赖。
本机没有 `ruff`，未将其宣称为本地已通过；PR 的 CI lint 仍须以最终 SHA 结果为准。

## 尚未关闭的门槛

- 该提交后的候选 SHA 尚未做新的双 Ubuntu 一次性 VM 验收。
- 草稿 PR 尚未独立复核、合并；没有 tag、正式 Release 或审批记录。
