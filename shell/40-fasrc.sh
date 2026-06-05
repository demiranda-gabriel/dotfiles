# FASRC (Harvard Cannon) — SLURM allocation helpers + VSCode-on-compute-node.
# Sourced on every cluster by the shell/*.sh loop, but no-ops unless the FASRC
# scratch mount exists, so FASRC-only partitions never leak onto other clusters.
if [[ -d /n/netscratch ]]; then

# Interactive session allocation function
interactive_session() {
    local device="cpu"
    local test="false"
    local n_nodes=1
    local n_tasks_per_node=1
    local cpu_per_task=2
    
    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            device=*)
                device="${1#*=}"
                shift
                ;;
            test=*)
                test="${1#*=}"
                shift
                ;;
            n_nodes=*)
                n_nodes="${1#*=}"
                shift
                ;;
            n_tasks_per_node=*)
                n_tasks_per_node="${1#*=}"
                shift
                ;;
            cpu_per_task=*)
                cpu_per_task="${1#*=}"
                shift
                ;;
            *)
                echo "Unknown parameter: $1"
                echo "Usage: interactive_session [device=->cpu|gpu] [test=true|->false] [n_nodes=1] [n_tasks_per_node=1] [cpu_per_task=2]"
                echo "Example: interactive_session device=gpu test=true n_nodes=1 n_tasks_per_node=1 cpu_per_task=1"
                return 1
                ;;
        esac
    done
    
    # Print allocation information
    echo "Allocating job: device=$device, test=$test, n_nodes=$n_nodes, n_tasks_per_node=$n_tasks_per_node, cpu_per_task=$cpu_per_task"
    
    # Build salloc command based on parameters
    if [[ "$test" == "true" ]]; then
        # Use test partition based on device
        if [[ "$device" == "gpu" ]]; then
            echo "Using partition: gpu_test"
            salloc -p gpu_test --gres gpu:1 -t 0-04:00 -N "$n_nodes" --ntasks-per-node="$n_tasks_per_node" --cpus-per-task="$cpu_per_task"
        else
            echo "Using partition: test"
            salloc -p test --mem 8000 -t 0-04:00 -N "$n_nodes" --ntasks-per-node="$n_tasks_per_node" --cpus-per-task="$cpu_per_task"
        fi
    elif [[ "$device" == "gpu" ]]; then
        # GPU allocation
        echo "Using partition: kozinsky_gpu,gpu"
        salloc -p kozinsky_gpu,gpu -t 0-06:00 -N "$n_nodes" --ntasks-per-node="$n_tasks_per_node" --gpus-per-node="$n_tasks_per_node" --cpus-per-task="$cpu_per_task" --gres=gpu:"$n_tasks_per_node" --constraint=a100 --mem-per-gpu=120000
    else
        # CPU allocation
        echo "Using partition: sapphire,kozinsky"
        salloc -p sapphire,kozinsky -t 0-12:00 -N "$n_nodes" --ntasks-per-node="$n_tasks_per_node" --cpus-per-task="$cpu_per_task" --mem-per-cpu=8G
    fi
}

export SCRATCH='/n/netscratch/kozinsky_lab/Lab/demiranda'
alias cds='cd $SCRATCH'
alias cdl='cd /n/holylabs/LABS/kozinsky_lab/Users/demiranda'
alias gpu_is='srun --pty -p gpu_test --gres gpu:1 --mem 8000 -t 0-01:00 /bin/bash'
alias lj='showq -u demiranda'
# name | status (sorted by status)
alias lq='squeue -u demiranda -S t -o "%.30j %.12T"'

alias is_test='srun --pty -p test --mem 8000 -t 0-04:00 /bin/bash'
alias is_gpu='salloc -p kozinsky_gpu,gpu,seas_gpu -t 0-06:00 -N 1 --ntasks-per-node=1 --cpus-per-task=2 --gres=gpu:1 --constraint=a100 --mem=64000'
alias is_gpu_1_32='salloc -p kozinsky_gpu,gpu -t 0-06:00 -N 1 --ntasks-per-node=1 --cpus-per-task=32 --gres=gpu:1 --constraint=a100 --mem=64000'
alias is_gpu_2='salloc -p kozinsky_gpu,gpu -t 0-06:00 -N 1 --ntasks-per-node=2 --gpus-per-node=2 --cpus-per-task=8 --gres=gpu:2 --constraint=a100 --mem-per-gpu=120000'
alias is_cpu='salloc -p sapphire,kozinsky -t 0-12:00 -N 1 --ntasks-per-node=1 --cpus-per-task=16 --mem-per-cpu=8G'

  # VSCode Remote-SSH on a compute node (toolkit: ~/scripts/vscode → dotfiles/scripts/vscode)
  alias vscode='~/scripts/vscode/vscode-up.sh up'
  alias vscode-status='~/scripts/vscode/vscode-up.sh status'
  alias vscode-down='~/scripts/vscode/vscode-up.sh down'
  alias tunnel='cd ~/scripts/vscode && sbatch vscode.job && tail -F out'
fi
