# P0-3：当前分支控制端基线的本地复核

日期：2026-09-24。受检提交：`d35dedd936ee1d2fad84e51715a7def97c0264ae`，
分支 `codex/devopstoolkit-hardening`，相对 `main` 的 merge-base 为
`74ef67b11b760a63d53f4f8f975d5e19fcf07405`。本轮没有安装宿主机软件、
修改 GitHub、推送或发布。

## 核验范围与结果

- 核对 `install.sh`、`ansible/requirements.yml`、`ansible/collections.lock.json`、
  `env-check.yml` 与 `release.yml`：控制端固定 `ansible-core 2.21.4`，CI Validate
  矩阵为 Python 3.12/3.14；三项 collection 的版本、归档 SHA256 和已安装目录通过
  `scripts/verify-collection-lock.py` 联合校验。隔离运行时实测输出为
  `ansible-playbook [core 2.21.4]`、Python 3.14.6。
- 在该提交执行完整 `./tests/verify-ansible.sh`，退出码 0。命令使用现有的隔离运行时和
  已锁定 collections：

```bash
PATH=/private/tmp/devopstoolkit-p03-managed/runtime/ansible-core-2.21.4/bin:$PATH \
ANSIBLE_COLLECTIONS_PATH=/private/tmp/devopstoolkit-p14.hcJpFA/collections \
./tests/verify-ansible.sh
```

- 使用同一批已校验的 collection 归档与安装目录，执行本地
  `./scripts/build-release.sh v0.1.8 <隔离临时目录>`，退出码 0。候选包的
  `VERSION` 为 `v0.1.8`，包含 `.bundled-collections` marker，未包含
  `AcmeConfig/` 或 runtime；`shasum -a 256 -c` 通过，tarball SHA256 为
  `7082b7ad9ebf1c8eb1119a3266edf3f3e84ade660eca8b8d2f0ae7197eb6d5b3`。
  临时候选包与隔离目录已清理，无法从本报告恢复。该哈希只对应这次本地构建，
  不是正式发布资产或 bit-for-bit 可复现性承诺。

## 仍需独立验收

以上不证明 GitHub Validate 在 Python 3.12/3.14 对同一 SHA 的远端通过、可信
Multipass runner 的定期报告、正式签名 Release、全新控制端安装或升级回滚。
当前 `gh auth status` 返回凭据无效；在重新认证并复核远端状态前，不改变 P0-3
的开放状态，也不推送或创建 tag。
