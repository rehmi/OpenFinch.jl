module Dashboard

using JSServe, WGLMakie
using GeometryBasics
using FileIO
using JSServe: @js_str, onjs, App, Slider
using JSServe.DOM


using JSServe, Observables
using JSServe: @js_str, Session, App, onjs, onload, Button
using JSServe: TextField, Slider, linkjs

using Markdown
using WGLMakie: volume



# set_theme!(resolution=(1200, 800))

hbox(args...) = DOM.div(args...)
vbox(args...) = DOM.div(args...)

# JSServe.browser_display()

##

end
