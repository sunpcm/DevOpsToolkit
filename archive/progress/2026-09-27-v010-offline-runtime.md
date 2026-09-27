# v0.1.10 已安装 runtime 的断网复用

正式来源 SHA：`571a5fef119055470d33ff478c0f69ba0524b1c5`。
环境：Ubuntu 24.04.5 aarch64、Python 3.12.3，一次性 VM。
先以普通用户安装正式 v0.1.10（SHA256/Sigstore 验证、core 2.21.4 和 bundled collections），
再执行独立网络命名空间内的普通用户测试：

```sh
multipass exec devops-toolkit-v010-offline-test-20260927 -- \
  sudo unshare --net runuser -u ubuntu -- bash /home/ubuntu/offline-acceptance.sh
```

[脚本](2026-09-27-v010-offline-acceptance.sh) SHA256：
`22b64dbeff770e7d454ad0c1eb550a2e033cf4d0da0988d0ef674ef12531334b`。
[完整输出](2026-09-27-v010-offline-output.txt) SHA256：
`4bded764dffeeae98450547717a09fd2c3c9f62a3f4a176f492edbb508521bfa`。
原始输出与临时日志逐字一致；宿主执行会话退出码 0，日志末尾 `offline_exit_code=0`。

## 结果与范围

- 普通用户 uid 1000；隔离命名空间仅有 DOWN 的 loopback、无路由，
  curl 禁用代理后无法访问外网；未断开宿主机或 VM 管理接口。
- source 精确来源安装器，仅调用 `ensure_managed_runtime` 两次；均复用已有 core 2.21.4，
  `.ready` inode、mtime、size 未变，未触发联网 pip 安装。
- current 包装器使用隔离 runtime，普通用户入口返回 v0.1.10；
  user-only syntax-check 能读取已安装 collections。该检查未执行配置任务。
- 最后确认 VM 无挂载和快照，仅停止并永久删除本次命名实例；
  `multipass list --format json` 独立回查为空，原始证据保留。

这证明已安装 runtime 可以在断网条件下复用，不证明完整安装器可以离线下载/安装，
也不关闭 macOS、WSL2、amd64、完整 Playbook 或发布保护负例。
独立复核结论 APPROVED：实际核对脚本/输出摘要、联网准备日志与清理空列表，
确认可以关闭上述精确范围的原 P0-3 离线复用门槛，不扩大到其他平台或离线完整安装。
