bin = /usr/local/bin/vera
# This is not the normal directory for bash completion
completion = /etc/bash_completion.d/vera
all:
	ln -svf ${PWD}/veracrypt.sh ${bin}
	ln -svf ${PWD}/completion.sh ${completion}
	chmod -v +x ${PWD}/veracrypt.sh ${PWD}/completion.sh
clean:
	rm -vf ${bin} ${completion}
