if [[ "${CURROS}" == "Darwin" ]]; then
    alias make='gmake'
    if [[ -d "/opt/homebrew/opt/binutils/bin" ]]; then
        add_to PATH "/opt/homebrew/opt/binutils/bin"
    fi
fi
