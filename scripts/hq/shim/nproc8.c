/* Fake CPU count for thread pools that ignore the cgroup/affinity limit
 * (libstdc++ std::thread::hardware_concurrency -> get_nprocs). ALCF login
 * nodes cap each user at 8 cores / 256 pids; HiGHS inside hq sizes its pool
 * to raw core count without this. Build:
 *   gcc -shared -fPIC -o nproc8.so nproc8.c
 * If your login cgroup grants a different core count, change 8 to match. */
int get_nprocs(void) { return 8; }
int get_nprocs_conf(void) { return 8; }
