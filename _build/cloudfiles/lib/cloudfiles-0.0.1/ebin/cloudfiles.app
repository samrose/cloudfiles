{application,cloudfiles,
             [{description,"Rackspace Cloud Files in Erlang"},
              {vsn,"0.0.1"},
              {modules,[cloudfiles,cloudfiles_app,cloudfiles_sup,mime_lib]},
              {registered,[cloudfiles_sup]},
              {applications,[kernel,stdlib]},
              {mod,{cloudfiles_app,[]}},
              {start_phases,[]}]}.
