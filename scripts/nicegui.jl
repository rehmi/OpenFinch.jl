

# pywebview = pyimport("webview")
# nicegui = pyimport("nicegui")
# ui = nicegui.ui

# ui.icon("thumb_up")
# ui.markdown("This is **Markdown**.")
# ui.html("This is <strong>HTML</strong>.")
# with ui.row():
#     ui.label("CSS").style("color: #888; font-weight: bold")
#     ui.label("Tailwind").classes("font-serif")
#     ui.label("Quasar").classes("q-ml-xl")
# ui.link("NiceGUI on GitHub", "https://github.com/zauberzeug/nicegui")

# ui.run(native=true)


##

using PythonCall

nicegui = pyimport("nicegui")
ui = nicegui.ui
events = nicegui.events
ValueChangeEventArguments = events.ValueChangeEventArguments

function pyshow(event) #: ValueChangeEventArguments):
    name = @py type(event.sender).__name__
    ui.notify("$name: $(event.value)")
end

jlshow = pyfunc(pyshow)

container = ui.card()

##

container.clear()

pywith(container) do val
	# ui.button("Button", on_click=@pyeval `lambda: ui.notify("Click")`)
	ui.button("Button", on_click=pyfunc() do _; ui.notify("Click"); end)

	pywith(ui.row()) do val
		ui.checkbox("Checkbox", on_change=jlshow)
		ui.switch("Switch", on_change=jlshow)
	end

	# label = ui.label()
	# ui.timer(1.0, pyfunc() do _
	# 	label.set_text(repr(now()))
	# end)

	ui.radio(pylist(["A", "B", "C"]), value="A", on_change=jlshow).props("inline")

	pywith(ui.row()) do val
		ui.input("Text input", on_change=jlshow)
		ui.select(pylist(["One", "Two"]), value="One", on_change=jlshow)
	end

	ui.link("And many more...", "/documentation").classes("mt-8")
end

##

ui.run()
```
##
