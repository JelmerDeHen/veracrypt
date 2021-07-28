DOT=/.../linux/sh/d/bashrc.d/668-veracrypt.sh
link = ln -svf ${PWD}/veracrypt.sh ${DOT}
all:
	$(link)
# ln -svf ${PWD}/veracrypt.sh /.../linux/sh/d/bashrc.d/668-veracrypt.sh
