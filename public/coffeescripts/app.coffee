class Services extends Backbone.Collection
  url: "/services"

class WebReports extends Backbone.Router

  routes:
    "": "index"
    "models": "models"
    "templates": "templates"

  models: ->
    collection = new Services
    @load new ModelReport {collection}

  templates: ->
    collection = new Services
    @load new TemplateReport {collection}

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
   "click .templates": -> Backbone.history.navigate("/templates", {trigger: true})


class Report extends Backbone.View

  TEMPLATE: _.template """
    <h2><%= subject %> Comparison</h2>
    <div class="sort-buttons btn-group">
      <a class="btn active sort-name">Sort by template name</a>
      <a class="btn sort-ubiquity">Sort by ubiquity</a>
    </div>
    <table class="table">
      <thead>
        <tr>
          <th><%= unit %> Name</th>
          <% services.forEach(function(s) { %>
            <th><%- s.name %></th>
          <% }); %>
        </tr>
      </thead>
      <tbody class="comparisons"></tbody>
    </table>
  """

  events: ->
    "click .sort-ubiquity": "sortByUbiquity"
    "click .sort-name": "sortByName"

  render: ->
    @collection.fetch(reset: true).then =>
      data = {@subject, @unit, services: @collection.toJSON()}
      @$el.empty().append(@TEMPLATE data)
      @collection.each @compareService
    @

  initialize: ->
    @units = new Backbone.Collection
    @units.comparator = 'name'
    @units.on "updated", @drawComparison, @

  toggleSortButtons: (evt) ->
    @$('.sort-buttons a').removeClass 'active'
    $(evt.target).addClass 'active'

  sortByName: (evt) ->
    @toggleSortButtons(evt)
    @units.comparator = 'name'
    @units.sort()
    @units.trigger("updated")

  sortByUbiquity: (evt) ->
    @toggleSortButtons(evt)
    @units.comparator = (unit) -> unit.get('presentIn').length
    @units.sort()
    @units.trigger("updated")

  drawComparison: ->
    fragment = document.createDocumentFragment()
    snames = @collection.pluck('name')
    @units.each (unit) =>
      tr = @compare unit, snames
      fragment.appendChild(tr.el)
      tr.render()
    $tbody = @$ '.comparisons'
    $tbody.empty().append(fragment)

class TemplateReport extends Report

  subject: 'Public Template'
  unit: 'Template'

  compare: (template, snames) ->
    new TemplateComparison model: template, services: snames

  compareService: (service) =>
    s = new intermine.Service root: service.get('root')
    s.fetchTemplates().then (templateMapping) =>
      for name, template of templateMapping
        @registerTemplate name, template, service
        @updateTemplate name, template, service
      @units.trigger "updated"

  registerTemplate: (name, template, service) ->
    unless @units.findWhere {name}
      @units.add {name, select: {}, where: {}, presentIn: []}

  updateTemplate: (name, template, service) ->
    tm = @units.findWhere {name}
    tm.get('presentIn').push(service.get('name'))
    return unless template.select and template.where
    select = tm.get('select')
    for path in template.select
      sm = new PathModel path
      key = sm.key()
      if key of select
        sm = select[key]
      else
        select[key] = sm
      sm.set foundIn: sm.get('foundIn').concat([service])

    where = tm.get('where')
    for constraint in template.where
      cm = new ConstraintModel constraint
      key = cm.key()
      if key of where
        cm = where[key]
      else
        where[key] = cm
      cm.set foundIn: cm.get('foundIn').concat([service])

class ModelReport extends Report

  subject: 'Model'
  unit: 'Class'

  compare: (cls, snames) -> new ClassComparison model: cls, services: snames

  compareService: (service) =>
    s = new intermine.Service(root: service.get('root'))
    s.fetchModel().then ({classes}) =>
      for name, cls of classes
        @registerClass name, cls, service
        @updateClass name, cls, service
      @units.trigger "updated"

  registerClass: (name, cls, service) ->
    unless @units.findWhere {name}
      @units.add {name, fields: {}, presentIn: []}

  updateClass: (name, cls, service) ->
    cm = @units.findWhere {name}
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

class FieldModel extends Backbone.Model

  initialize: (fld) ->
    @set foundIn: [], type: (fld.type or fld.referencedType)

  key: -> "#{ @get('name') }::#{ @get('type') }"

class PathModel extends Backbone.Model

  initialize: (path) ->
    @set foundIn: [], path: path

  key: -> @get 'path'

class ConstraintModel extends Backbone.Model

  initialize: (constraint) ->
    @set foundIn: []

  key: -> "#{ @get('path') } #{ @get('op') }"

class Comparison extends Backbone.View

  tagName: 'tr'
  className: 'comparison'

  initialize: ->
    @services = @options.services

  events: ->
    "click td.name": "toggleDetails"

  render: ->
    {name, presentIn} = @model.toJSON()
    @el.appendChild(tableCell(name, className: "name"))
    for sname in @services
      there = if sname in presentIn then "yes" else "no"
      @el.appendChild(tableCell(there, {className: there}))
    @

class ClassComparison extends Comparison

  toggleDetails: ->
    if fc = @fieldComparison?
      fc.remove()
      @fieldComparison = null
    else
      fc = @fieldComparison = new FieldComparison {@model, @services}
      fc.render().$el.insertAfter(@el)

  remove: ->
    @fieldComparison?.remove()
    super()

class TemplateComparison extends Comparison

  toggleDetails: ->
    if vc = @viewComparison
      vc.remove()
      @viewComparison = null
    else
      vc = @viewComparison = new ViewComparison {@model, @services}
      vc.render().$el.insertAfter @el

    if cc = @constraintComparison
      cc.remove()
      @constraintComparison = null
    else
      cc = @constraintComparison = new ConstraintComparison {@model, @services}
      cc.render().$el.insertAfter @el

  remove: ->
    @viewComparison?.remove()
    @constraintComparison?.remove()
    super()

class DetailComparison extends Backbone.View

  tagName: 'tr'
  className: 'comparison'

  render: ->
    tab = document.createElement('table')
    td = document.createElement('td')
    td.colSpan = @options.services.length + 1
    @el.appendChild td
    td.appendChild tab
    head = document.createElement('thead')
    headR = document.createElement('tr')
    head.appendChild(headR)
    for t in [@thContent].concat(@options.services)
      headR.appendChild(textElem('th', t))
    tab.appendChild(head)
    body = document.createElement('tbody')

    things = @model.toJSON()[@detail]

    for key, model of things
      foundIn = model.get('foundIn')
      tr = document.createElement('tr')
      nameCell = document.createElement('td')
      for child in @detailParts(model)
        nameCell.appendChild(child)
      tr.appendChild(nameCell)
      for s in @options.services
        there = if _.any(foundIn, (m) -> m.get('name') is s) then "yes" else "no"
        tr.appendChild(tableCell(there, {className: there}))
      body.appendChild tr

    tab.appendChild body

    @

class FieldComparison extends DetailComparison

  thContent: "field name"
  detail: 'fields'

  detailParts: (fieldModel) -> [
      textElem('span', fieldModel.get('name'), className: 'field-name'),
      textElem('span', fieldModel.get('type'), className: 'field-type')
  ]

class ViewComparison extends DetailComparison

  thContent: "selected path"
  detail: 'select'

  detailParts: (pathModel) -> [
      textElem('code', pathModel.get('path'), className: 'selected-path')
  ]

class ConstraintComparison extends DetailComparison

  thContent: "constraint"
  detail: "where"

  detailParts: (constraintModel) -> [
      textElem('code', constraintModel.get('path'), className: 'constrained-path'),
      textElem('span', " "),
      textElem('code', constraintModel.get('op'), className: 'constraint-operator'),
      textElem('span', " "),
      textElem('span', "something")
  ]

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
