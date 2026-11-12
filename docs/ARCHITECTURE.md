# r16 当前架构

书库 Scriptlet → setsid supervisor → 独占 session.lock → 复制每会话 runtime/恢复脚本 → 兼容性探测 → 独立 guard → 精确记录原版 UI PID/starttime → STOP 指定 UI（保留 lab126_gui/init）→ 保存 framebuffer → 电源订阅/控制器 → LuaJIT 主程序。

主程序：Config / Registry / Scheduler / App；native FreeType 字形→灰度 canvas→mmap 可见 framebuffer→每帧一个 FBInk GC16。Canvas 与 framebuffer 尺寸必须一致。部分刷新采用实际像素 diff bbox。字体/蒙版缓存有数量和字节上限，JSON 深度64、节点50000，HTTP四槽/单响应4MiB、滴答聚合4MiB/2000任务/24层/25清单、64标签加溢出提示、512展示页。

本地 FBInk/LIPC 命令8秒deadline，TERM后1秒KILL，刷新只重试一次；持久失败非零退出。HTTP由后台shell+curl执行，curl自带timeout，worker在请求前发布PID/starttime；Lua轮询done，180秒模块异步看护。取消停止拥有的curl和worker，身份不明时保留取消标记；完成的run目录下次启动清理。

所有自动周期共享anchor。`no_coalesce=true`，不提前合并不同到期任务；回调只置dirty，按共同显示时隙上屏。手动刷新批次最长等60秒，点击/完成动作允许立即反馈。暂停不启动新自动任务，已在途请求收尾。

退出先停应用/网络/电源子进程，恢复stock.fb和首次GC16清理，CONT同一UI进程，恢复preventScreenSaver，等待/校验UI状态，请求Home，再等待并第二次GC16清理。完整成功才释放所有权锁；最多自动恢复3次，单次恢复看护60秒。失败保留快照与锁；显式Recovery提供新预算。SIGKILL通常由guard处理，不保证内核/IO彻底失常时仍可恢复。

PC配置写入：OS锁+原始摘要复核+本机加密备份+设备pending journal+每文件fsync/replace；读取只读；中断后显式恢复。设备启动拒绝pending journal。两文件不能在FAT上同时原子提交。
