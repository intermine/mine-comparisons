class Services extends Backbone.Collection
  url: "/services"

class WebReports extends Backbone.Router

  routes:
    "": "index"
    "models": "models"
    "templates": "templates"

  models: ->
    console.log "Loading models"
    collection = new Services
    modelReport = new ModelReport {collection}
    @load modelReport

  index: -> @load new MainMenu

  load: (view) ->
    @main?.remove()
    @main = view
    view.render()
    document.getElementById('main').appendChild(@main.el)

class MainMenu extends Backbone.View

  TEMPLATE: """
    <div>
      <ul class="thumbnails">
        <li class="span6">
          <div class="thumbnail models">
            <img src="/images/models.png" alt="models">
            <a href="/models">Compare Models</a>
          </div>
        </li>
        <li class="span6">
          <div class="thumbnail templates">
            <img src="/images/templates.png" alt="models">
            <a href="/templates">Compare Templates</a>
          </div>
        </li>
      </ul>
    </div>
  """

  render: ->
    @$el.append @TEMPLATE
    @

  events: ->
   "click a": (evt) -> evt.preventDefault()
   "click .models": -> Backbone.history.navigate("/models", {trigger: true})

class ModelReport extends Backbone.View

  TEMPLATE: _.template """
    <h2>Model Comparision</h2>
    <div class="sort-buttons btn-group">
      <a class="btn active sort-class-name">Sort by class name</a>
      <a class="btn sort-ubiquity">Sort by ubiquity</a>
    </div>
    <table class="table">
      <thead>
        <tr>
          <th>Class Name</th>
          <% services.forEach(function(s) { %>
            <th><%- s.name %></th>
          <% }); %>
        </tr>
      </thead>
      <tbody class="class-comparisons"></tbody>
    </table>
  """

  events: ->
    "click .sort-ubiquity": "sortByUbiquity"
    "click .sort-class-name": "sortByClassName"

  toggleSortButtons: (evt) ->
    @$('.sort-buttons a').removeClass 'active'
    $(evt.target).addClass 'active'

  sortByClassName: (evt) ->
    @toggleSortButtons(evt)
    @classes.comparator = 'name'
    @classes.sort()
    @classes.trigger("updated")

  sortByUbiquity: (evt) ->
    @toggleSortButtons(evt)
    @classes.comparator = (cls) -> cls.get('presentIn').length
    @classes.sort()
    @classes.trigger("updated")

  initialize: ->
    @classes = new Backbone.Collection
    @classes.comparator = 'name'
    @classes.on "updated", @drawComparison, @

  render: ->
    @collection.fetch(reset: true).then =>
      @$el.empty()
          .append(@TEMPLATE services: @collection.toJSON())
      @collection.each @compareService
    @

  compareService: (service) =>
    s = new intermine.Service(root: service.get('root'))
    s.fetchModel().then ({classes}) =>
      for name, cls of classes
        @registerClass name, cls, service
        @updateClass name, cls, service
      @classes.trigger "updated"

  registerClass: (name, cls, service) ->
    unless @classes.findWhere {name}
      @classes.add {name, fields: {}, presentIn: []}

  updateClass: (name, cls, service) ->
    cm = @classes.findWhere {name}
    fields = cm.get('fields')
    cm.get("presentIn").push(service.get("name"))
    for name, fld of cls.fields
      fm = new FieldModel fld
      fkey = fm.key()
      if fkey of fields
        fm = fields[fkey]
      else
        fields[fkey] = fm
      fm.set foundIn: fm.get('foundIn').concat([service])

  drawComparison: ->
    fragment = document.createDocumentFragment()
    snames = @collection.pluck('name')
    @classes.each (cls) ->
      tr = new ClassComparison model: cls, services: snames
      fragment.appendChild(tr.el)
      tr.render()
    $tbody = @$ '.class-comparisons'
    $tbody.empty().append(fragment)

class FieldModel extends Backbone.Model

  initialize: (fld) ->
    @set foundIn: [], type: (fld.type or fld.referencedType)

  key: -> "#{ @get('name') }::#{ @get('type') }"


class ClassComparison extends Backbone.View

  tagName: 'tr'
  className: 'cd-comparison'

  initialize: ->
    @services = @options.services

  events: ->
    "click td.name": "toggleFields"

  render: ->
    {name, presentIn} = @model.toJSON()
    @el.appendChild(tableCell(name, className: "name"))
    for sname in @services
      there = if sname in presentIn then "yes" else "no"
      @el.appendChild(tableCell(there, {className: there}))
    @

  toggleFields: ->
    if @fieldComparison?
      @fieldComparison.remove()
      @fieldComparison = null
    else
      @fieldComparison = new FieldComparison {@model, @services}
      @fieldComparison.render().$el.insertAfter(@el)

  remove: ->
    @fieldComparision?.remove()
    super()

class FieldComparison extends Backbone.View

  tagName: 'tr'
  className: 'fd-comparison'

  render: ->
    tab = document.createElement('table')
    td = document.createElement('td')
    td.colSpan = @options.services.length + 1
    @el.appendChild td
    td.appendChild tab
    head = document.createElement('thead')
    headR = document.createElement('tr')
    head.appendChild(headR)
    for t in ["field name"].concat(@options.services)
      headR.appendChild(textElem('th', t))
    tab.appendChild(head)
    body = document.createElement('tbody')

    {fields} = @model.toJSON()
    for key, fm of fields
      foundIn = fm.get('foundIn')
      tr = document.createElement('tr')
      nameCell = document.createElement('td')
      nameCell.appendChild(textElem('span', fm.get('name'), className: 'field-name'))
      nameCell.appendChild(textElem('span', fm.get('type'), className: 'field-type'))
      tr.appendChild(nameCell)
      for s in @options.services
        there = if _.any(foundIn, (m) -> m.get('name') is s) then "yes" else "no"
        tr.appendChild(tableCell(there, {className: there}))
      body.appendChild tr

    tab.appendChild body

    @

tableCell = (txt, opts) -> textElem 'td', txt, opts

textElem = (tag, txt, opts) ->
  el = document.createElement(tag)
  if opts?
    for prop, val of opts
      el[prop] = val
  return text(el, txt)

text = (node, txt) ->
  node.appendChild(document.createTextNode(txt))
  return node

main = ->

  new WebReports
  console.log "Starting backbone history"
  Backbone.history.start pushState: true

$ main
