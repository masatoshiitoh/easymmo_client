REBAR:=rebar
 
.PHONY: all erl test clean doc
 
all: erl
 
erl:
	$(REBAR) get-deps compile
 
test: all
	@mkdir -p .eunit
	$(REBAR) skip_deps=true eunit
 
clean:
	$(REBAR) clean
	-rm -rvf deps ebin doc .eunit
 
doc:
	$(REBAR) doc

release:
	$(REBAR) get-deps compile
	cd rel; $(REBAR) generate

run:
	./rel/easymmo_client/bin/easymmo_client start

stop-app:
	./rel/easymmo_client/bin/easymmo_client stop

console:
	./rel/easymmo_client/bin/easymmo_client attach
