function f
    argparse --max-args 1 \
    --exclusive 'h,s,d,v,o,e,reset' \
        'h/help' \
        's/save' \
        'd/delete' \
        'v/view' \
        'o/open' \
        'e/edit' \
        'reset' -- $argv

    set -l query $argv

    # fast will write project path to file descriptor 3
    # fish doesn't support reading to file descriptor so use bash
    set -l tmp_file /tmp/fast_project
    rm -f $tmp_file

    if test $_flag_help
        fast --help
    else if test $_flag_save
        fast --save $query
    else if test $_flag_delete
        fast --delete $query
    else if test $_flag_view
        fast --view $query
    else if test $_flag_open
        fast --open $query
    else if test $_flag_edit
        bash -c "exec 3<> $tmp_file && fast --edit $query"
        if test $status -eq 0
            set -l dir (cat $tmp_file)
            cd $dir
            $EDITOR $dir
        end
    else if test $_flag_reset
        fast --reset
    else
        bash -c "exec 3<> $tmp_file && fast $query"
        if test $status -eq 0
            set -l dir (cat $tmp_file)
            cd $dir
        end
    end

    bash -c "exec 3>&-"
end
