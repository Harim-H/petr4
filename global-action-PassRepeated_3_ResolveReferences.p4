@name(".Global") action Global() {
}
control c() {
    @name(".Global") action Global_0() {
    }
    @name("t") table t_0 {
        actions = {
            Global_0();
        }
        default_action = Global_0();
    }
    apply {
        t_0.apply();
    }
}

control none();
package top(none n);
top(c()) main;

