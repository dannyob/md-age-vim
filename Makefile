# md-age-vim Makefile

TESTIFY_DIR := deps/vim-testify
VIM := nvim

.PHONY: test test-vim test-cli test-tap test-vim-tap test-cli-tap deps clean

test: test-vim test-cli

test-tap: test-vim-tap test-cli-tap

test-vim: deps
	$(VIM) --headless -u NONE \
		-c "set rtp+=$(TESTIFY_DIR)" \
		-c "set rtp+=." \
		-c "runtime plugin/testify.vim" \
		-c "runtime plugin/md-age.vim" \
		+TestifySuite

test-cli:
	./t/md-age-test.sh

test-vim-tap: deps
	@$(VIM) --headless -u NONE \
		-c "set rtp+=$(TESTIFY_DIR)" \
		-c "set rtp+=." \
		-c "runtime plugin/testify.vim" \
		-c "runtime plugin/md-age.vim" \
		+TestifySuite 2>&1 | awk '/^√/ {n++; print "ok " n " - " substr($$0,3)} /^✗/ {n++; print "not ok " n " - " substr($$0,3)} /^  / {print "#" $$0} END {print "1.." n}'

test-cli-tap:
	@TAP=1 ./t/md-age-test.sh

deps: $(TESTIFY_DIR)

$(TESTIFY_DIR):
	@mkdir -p deps
	git clone --depth 1 https://github.com/dhruvasagar/vim-testify.git $(TESTIFY_DIR)

clean:
	rm -rf deps testify_results.txt
