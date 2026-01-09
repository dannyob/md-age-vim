# md-age-vim Makefile

TESTIFY_DIR := deps/vim-testify
VIM := nvim

.PHONY: test test-vim test-cli deps clean

test: test-vim test-cli

test-vim: deps
	$(VIM) --headless \
		-c "set rtp+=$(TESTIFY_DIR)" \
		-c "set rtp+=." \
		-c "runtime plugin/testify.vim" \
		-c "runtime plugin/md-age.vim" \
		+TestifySuite

test-cli:
	./t/md-age-test.sh

deps: $(TESTIFY_DIR)

$(TESTIFY_DIR):
	@mkdir -p deps
	git clone --depth 1 https://github.com/dhruvasagar/vim-testify.git $(TESTIFY_DIR)

clean:
	rm -rf deps testify_results.txt
