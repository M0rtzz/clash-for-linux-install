function clashctl
    set -l command_name help
    if test (count $argv) -gt 0
        set command_name $argv[1]
    end
    switch $command_name
        case on
            set -l rest $argv[2..-1]
            if contains -- -s $rest; or contains -- --service-only $rest; or contains -- -h $rest; or contains -- --help $rest
                command clashctl $argv
            else if contains -- -e $rest; or contains -- --env-only $rest
                command clashctl status >/dev/null; and command clashctl env --shell=fish | source
            else
                command clashctl on --service-only $rest; and command clashctl env --shell=fish | source
            end
        case off
            set -l rest $argv[2..-1]
            if contains -- -s $rest; or contains -- --service-only $rest; or contains -- -h $rest; or contains -- --help $rest
                command clashctl $argv
            else
                if not contains -- -e $rest; and not contains -- --env-only $rest
                    command clashctl off --service-only $rest; or return
                end
                set -e http_proxy HTTP_PROXY https_proxy HTTPS_PROXY all_proxy ALL_PROXY no_proxy NO_PROXY
            end
        case '*'
            command clashctl $argv
    end
end
