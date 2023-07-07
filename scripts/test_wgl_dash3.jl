using JSServe, JSServe.DOM
using JSServe: @js_str, onjs, App, Slider
using JSServe: @js_str, Session, App, onjs, onload, Button
using JSServe: TextField, Slider, linkjs

using WGLMakie, GeometryBasics, FileIO
using WGLMakie: volume

using Observables, Markdown

##

# set_theme!(resolution=(1200, 800))

hbox(args...) = DOM.div(args...)
vbox(args...) = DOM.div(args...)

JSServe.browser_display()

##

# app = App() do
#     return hbox(vbox(
#         volume(rand(4, 4, 4), isovalue=0.5, isorange=0.01, algorithm=:iso),
#         volume(rand(4, 4, 4), algorithm=:mip),
#         volume(1..2, -1..1, -3..(-2), rand(4, 4, 4), algorithm=:absorption)),
#         vbox(
#         volume(rand(4, 4, 4), algorithm=Int32(5)),
#         volume(rand(RGBAf, 4, 4, 4), algorithm=:absorptionrgba),
#         contour(rand(4, 4, 4)),
#     ))
# end

# ##

# color = Observable("red")
# color_css = map(x-> "color: $(x)", color)

# app = App() do
#     return DOM.h1("Hello World", style=map(x-> "color: $(x)", color))
# end
# display(app)

# ##

# color[] = "green"

# app = App() do
#     color = Observable("red")
#     on(println, color)
#     button = DOM.div("click me", onclick=js"""(e)=> {
#         const color = '#' + ((1<<24)*Math.random() | 0).toString(16)
#         console.log(color)
#         $(color).notify(color)
#     }""")
#     style = map(x-> "color: $(x)", color)
#     return DOM.div(
#         button, DOM.h1("Hello World", style=style)
#     )
# end
# display(app)

# ##

# app = App() do session::Session
#     color = Observable("red")
#     button = DOM.div("click me", onclick=js"e=> $(color).notify('blue')")
#     onload(session, button, js"""function load(button){
#         window.alert('Hi from JavaScript');
#     }""")

#     onjs(session, color, js"""function update(value){
#         window.alert(value);
#         // throw "heey!"
#     }""")

#     return DOM.div(
#         button, DOM.h1("Hello World", style=map(x-> "color: $(x)", color))
#     )
# end

# display(app)

# ##

# md"""
# # Including assets & Widgets
# """

# MUI = JSServe.Asset("https://cdn.muicss.com/mui-0.10.1/css/mui.min.css")
# sliderstyle = JSServe.Asset(joinpath(@__DIR__, "sliderstyle.css"))
# image = JSServe.Asset(joinpath(@__DIR__, "assets", "julia.png"))
# s = JSServe.get_server();

# app = App() do
#     button = JSServe.Button("hi", class="mui-btn mui-btn--primary")
#     slider = JSServe.Slider(1:10, class="slider")

#     on(button) do click
#         @show click
#     end

#     on(slider) do slidervalue
#         @show slidervalue
#     end
#     link = DOM.a(href="/example1", "GO TO ANOTHER WORLD")
#     return DOM.div(MUI, sliderstyle, link, button, slider, DOM.img(src=image))
# end
# display(app)

##

app = App() do
    cmap_button = Button("change colormap")
    algorithm_button = Button("change algorithm")
    algorithms = ["mip", "iso", "absorption"]
    algorithm = Observable(first(algorithms))
    dropdown_onchange = js"""(e)=> {
        const element = e.srcElement;
        ($algorithm).notify(element.options[element.selectedIndex].text);
    }"""
    algorithm_drop = DOM.select(DOM.option.(algorithms); class="bandpass-dropdown", onclick=dropdown_onchange)

    data_slider = Slider(LinRange(1.0f0, 10.0f0, 100))
    iso_value = Slider(LinRange(0.0f0, 1.0f0, 100))
    N = 100
    slice_idx = Slider(1:N)

    signal = map(data_slider.value) do α
        a = -1
        b = 2
        r = LinRange(-2, 2, N)
        z = ((x, y) -> x + y).(r, r') ./ 5
        me = [z .* sin.(α .* (atan.(y ./ x) .+ z .^ 2 .+ pi .* (x .> 0))) for x = r, y = r, z = r]
        return me .* (me .> z .* 0.25)
    end

    slice = map(signal, slice_idx) do x, idx
        view(x, :, idx, :)
    end

    fig = Figure()

    vol = volume(fig[1, 1], signal; algorithm=map(Symbol, algorithm), ambient=Vec3f0(0.8), isovalue=iso_value)

    colormaps = collect(Makie.all_gradient_names)
    cmap = map(cmap_button) do click
        return colormaps[rand(1:length(colormaps))]
    end

    heat = heatmap(fig[1, 2], slice, colormap=cmap)

    dom = md"""
    # More MD

    [Github-flavored Markdown info page](http://github.github.com/github-flavored-markdown/)

    [![Build Status](https://travis-ci.com/SimonDanisch/JSServe.jl.svg?branch=master)](https://travis-ci.com/SimonDanisch/JSServe.jl)

    Thoughtful example
    ======

    Alt-H2
    ------

    *italic* or **bold**

    Combined emphasis with **asterisks and _underscores_**.

    1. First ordered list item
    2. Another item
        * Unordered sub-list.
    1. Actual numbers don't matter, just that it's a number
        1. Ordered sub-list

    * Unordered list can use asterisks

    Inline `code` has `back-ticks around` it.
    ```julia
    test("haha")
    ```

    ---
    # JSServe

    [![Build Status](https://travis-ci.com/SimonDanisch/JSServe.jl.svg?branch=master)](https://travis-ci.com/SimonDanisch/JSServe.jl)
    [![Build Status](https://ci.appveyor.com/api/projects/status/github/SimonDanisch/JSServe.jl?svg=true)](https://ci.appveyor.com/project/SimonDanisch/JSServe-jl)
    [![Codecov](https://codecov.io/gh/SimonDanisch/JSServe.jl/branch/master/graph/badge.svg)](https://codecov.io/gh/SimonDanisch/JSServe.jl)
    [![Build Status](https://travis-ci.com/SimonDanisch/JSServe.jl.svg?branch=master)](https://travis-ci.com/SimonDanisch/JSServe.jl)


    | Tables        | Are           | Cool  |
    | ------------- |:-------------:| -----:|
    | col 3 is      | right-aligned | $1600 |
    | col 2 is      | centered      |   $12 |
    | zebra stripes | are neat      |    $1 |

    > Blockquotes are very handy in email to emulate reply text.
    > This line is part of the same quote.

    # Plots:

    $(DOM.div("data param", data_slider))

    $(DOM.div("iso value", iso_value))

    $(DOM.div("y slice", slice_idx))

    $(algorithm_drop)

    $(cmap_button)

    ---

    $(fig.scene)

    ---
    """
    return JSServe.DOM.div(JSServe.MarkdownCSS, JSServe.Styling, dom)
end

