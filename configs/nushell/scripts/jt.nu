use std assert
use std log

const CONFIG_PATH = ($nu.home-path | path join '.config' 'jt' 'jt.csv')

def alert [message: string] {
    print $"(ansi red)($message)(ansi reset)"
}

def warn [message: string] {
    print $"(ansi yellow)($message)(ansi reset)"
}

def info [message: string] {
    print $"(ansi green)($message)(ansi reset)"
}

export def --env main [
    --register (-r)  # Register new machine
    --list (-l)      # List all machines
    --delete (-d): int  # Delete machine by index
    address?: string  # Target machine address
] {
    if $register {
        register
    } else if $list {
        list
    } else if ($delete | is-not-empty) {
        delete-machine $delete
    } else if ($address | is-empty) {
        print-help
    } else {
        login $address
    }
}

def print-help [] {
    print (ansi green)
    print "Usage: jt [OPTION] [PARAMS]"
    print "Login different machines through IP or domain name and ssh"
    print ""
    print "Options:"
    print "  [address]        Jump to remote machine with ssh"
    print "  -r, --register   Register machine login information"
    print "  -l, --list       Show address list"
    print "  -d, --delete     Delete machine by index"
    print "  -h, --help       Show this help message"
    print (ansi reset)
}

def register [] {
    let ip = (input "Please input register ip: ")
    let user = (input "Please input register user: ")
    let port = (input "Please input register port: ")

    # Validate input
    if ($ip | is-empty) or ($user | is-empty) {
        alert "Invalid input: All fields except 2FA secret are required"
        return
    }
    let id_rsa_pub = (ls ~/.ssh | where name =~ '\.pub$' | first | get name)
    print $id_rsa_pub
    open $id_rsa_pub | ssh $"($user)@($ip)" "awk 1 ORS=\"\\n\" >> ~/.ssh/authorized_keys"

    let password = "any"
    # Encode password
    let crypted = ($password | encode base64)
    let line = $"($user),($ip),($crypted),($port)\n"

    # Append to config file
    let config_dir = ($CONFIG_PATH | path dirname)
    mkdir $config_dir
    $line | save $CONFIG_PATH --append
    let id_rsa_pub = (open --raw $CONFIG_PATH)

    info "Machine registered successfully!"
}

def list [] {
    if not ($CONFIG_PATH | path exists) {
        warn "No machines registered yet"
        return
    }

    open --raw $CONFIG_PATH | lines
}

def login [address: string] {
    if not ($CONFIG_PATH | path exists) {
        alert "No machines registered yet, use 'jt --register' first"
        return
    }

    let candidates = (open --raw $CONFIG_PATH
        | lines
        | each {|line|
            let parsed = ($line | split row ",")
            if ($parsed | length) != 4 {
                return null
            }

            {
                user: $parsed.0
                ip: $parsed.1
                password: $parsed.2
                port: $parsed.3
            }
        }
        | where {|it|
            ($it.ip | str ends-with $address) or ($it.user =~ $address)
        }
    )

    match ($candidates | length) {
        0 => { alert $"No machines found matching: ($address)" }
        1 => { connect ($candidates | first) }
        _ => {
            info "Multiple matches found:"
            $candidates
                | enumerate
                | each {|it|
                    {
                        $it.index: $"($it.item.user)@($it.item.ip):($it.item.port)"
                    } | print
                }

            let selected = (input "Select machine index: " | into int)
            connect ($candidates | get $selected)
        }
    }
}

def connect [record: record] {
    info $"Connecting to ($record.user)@($record.ip)..."

    let port = ($record.port? | default "22")
    ssh -o StrictHostKeyChecking=no -p $port $"($record.user)@($record.ip)"
}
