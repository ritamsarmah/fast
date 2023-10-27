function f
    # Binary writes command for shell to tmp file
    # This primarily avoids spawning a child process to change directory for example
    set -l tmp_file /tmp/fast_cmd
    rm -f "$tmp_file"

    # Forward arguments
    fast $argv

    set -l fast_status $status
    # Check if fast exited successfully and wrote command to tmp file
    if test $fast_status -eq 0 && test -e "$tmp_file"
        set -l cmd (cat $tmp_file)
        eval "$cmd"
    end

    # Exit with fast status
    return $fast_status
end
