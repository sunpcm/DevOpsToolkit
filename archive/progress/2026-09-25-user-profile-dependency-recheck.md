# P1-2：依赖安装报告成功后仍缺命令的 fail-closed 回归

日期：2026-09-25。代码基线：`main@9d613e85b4adaae4c9c8a5a7231556d68960b07e`。

`tests/test-orchestration.py` 从真实 `user-only.yml` 读取依赖检查到最终断言的
`pre_tasks`，只在临时 Playbook 中把 apt 任务替换成“报告成功”的 debug 任务。
目标命令故意不存在；测试确认 apt 模拟任务实际执行、二次命令检查仍发现缺失、
Playbook 以非零码终止并报告缺失命令，未进入后续 `user_profile` role。
测试使用本机临时目录与现有隔离 Ansible 运行时，不调用 sudo/apt，不安装软件，
不连接生产主机，也不修改用户 HOME。

可重复验证命令：

```bash
PATH=<已有 ansible-core 2.21.4 运行时>/bin:$PATH \
ANSIBLE_COLLECTIONS_PATH=<已校验的锁定 collections 路径> \
python3 tests/test-orchestration.py

PATH=<已有 ansible-core 2.21.4 运行时>/bin:$PATH \
ANSIBLE_COLLECTIONS_PATH=<已校验的锁定 collections 路径> \
./tests/verify-ansible.sh
```

两条命令均退出 0，完整门禁最终输出“统一 Ansible 入口静态验证通过”。
这只证明回归保护与任务顺序；它不能证明真正 apt 包安装、Ubuntu 22.04/24.04
干净 HOME 的两次收敛、登录 Shell 或语言工具下载。TODO 中的 P1-2 一次性 VM
验收仍开放，待取得临时 VM 内安装依赖的明确授权后执行。
