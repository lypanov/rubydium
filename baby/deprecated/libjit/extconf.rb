require 'mkmf'
dir_config("libjit")
have_library("jit", "jit_context_create")
$objs = ["ruby-libjit.o"]
create_makefile("libjit")
