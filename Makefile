bin = /usr/local/bin/vera
# This is not the normal directory for bash completion
completion = /etc/bash_completion.d/vera
all:
	ln -svf ${PWD}/vera.sh ${bin}
	ln -svf ${PWD}/completion.sh ${completion}
	chmod -v +x ${PWD}/vera.sh ${PWD}/completion.sh
clean:
	rm -vf ${bin} ${completion}
