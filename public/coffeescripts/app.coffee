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
    <a class="btn sort-invert">Invert Order</a>
    <div class="sort-buttons btn-group">
      <a class="btn active sort-name">Sort by name</a>
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

  compare = (a, b) -> if a > b then 1 else if a is b then 0 else -1
  ubiquity = (unit) -> unit.get('presentIn').length
  nameOf = (unit) -> unit.get('name')

  events: ->
    "click .sort-ubiquity": "sortByUbiquity"
    "click .sort-name": "sortByName"
    "click .sort-invert": "sortInvert"

  render: ->
    @collection.fetch(reset: true).then =>
      data = {@subject, @unit, services: @collection.toJSON()}
      @$el.empty().append(@TEMPLATE data)
      @collection.each @compareService
    @

  initialize: ->
    @units = new Backbone.Collection
    @sorting = new Backbone.Model
    @sorting.on "change", @updateSort, @
    @sorting.set by: 'name', direction: 'ASC'
    @units.on "updated", @drawComparison, @

  toggleButtons: (selector, evt) ->
    @$(selector + ' a').removeClass 'active'
    $(evt.target).addClass 'active'

  updateSort: ->
    fn = switch @sorting.get('by')
      when 'name' then nameOf
      when 'ubiquity' then ubiquity
      else throw new Error("Unknown sort property")

    sortFn = switch @sorting.get('direction')
      when 'ASC' then (a, b) -> compare fn(a), fn(b)
      when 'DESC' then (a, b) -> compare fn(b), fn(a)
      else throw new Error("Unknown sort direction")

    @units.comparator = sortFn
    @units.sort()
    @units.trigger("updated")

  sortByName: (evt) ->
    @toggleButtons('.sort-buttons', evt)
    @sorting.set by: 'name'

  sortByUbiquity: (evt) ->
    @toggleButtons('.sort-buttons', evt)
    @sorting.set by: 'ubiquity'

  sortInvert: (evt) ->
    $elem = $ evt.target
    wasActive = $elem.is '.active'
    $elem.toggleClass 'active'
    @sorting.set direction: (if wasActive then 'ASC' else 'DESC')

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
    select = tm.get('select')
    for path in (template.select or template.view)
      sm = new PathModel path
      key = sm.key()
      if key of select
        sm = select[key]
      else
        select[key] = sm
      sm.set foundIn: sm.get('foundIn').concat([service])

    where = tm.get('where')
    for constraint in (template.where or template.constraints)
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
      @units.add {name, parents: {}, fields: {}, presentIn: []}

  updateClass: (name, cls, service) ->
    cm = @units.findWhere {name}
    fields = cm.get('fields')
    parents = cm.get('parents')
    cm.get("presentIn").push(service.get("name"))
    for name, fld of cls.fields
      fm = new FieldModel fld
      fkey = fm.key()
      if fkey of fields
        fm = fields[fkey]
      else
        fields[fkey] = fm
      fm.set foundIn: fm.get('foundIn').concat([service])

    for parent in cls.parents()
      pm = new PathModel parent
      key = pm.key()
      if key of parents
        pm = parents[key]
      else
        parents[key] = pm
      pm.set foundIn: pm.get('foundIn').concat([service])


class FieldModel extends Backbone.Model

  initialize: (fld) ->
    @set foundIn: [], type: (fld.type or fld.referencedType)
    if fld.isCollection
      @set type: "Collection<#{ fld.referencedType }>"

  key: -> "#{ @get('name') }::#{ @get('type') }"

class PathModel extends Backbone.Model

  initialize: (path) ->
    @set foundIn: [], path: path

  key: -> @get 'path'

class ConstraintModel extends Backbone.Model

  initialize: (constraint) ->
    @set foundIn: []

  key: -> "#{ @get('path') } #{ @get('op') or @get('type') } #{ @get('switched') or 'LOCKED' }"

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

    if fc = @fieldComparison
      fc.remove()
      @fieldComparison = null
    else
      fc = @fieldComparison = new FieldComparison {@model, @services}
      fc.render().$el.insertAfter(@el)

    if ic = @inheritanceComparison
      ic.remove()
      @inheritanceComparison = null
    else
      ic = @inheritanceComparison = new InheritanceComparison {@model, @services}
      ic.render().$el.insertAfter(@el)

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
  className: 'detail comparison'

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
    models = _.sortBy(_.values(things), (m) -> m.get('name'))

    if models.length is 0
      @$el.empty()
      return @

    for model in models
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

class InheritanceComparison extends DetailComparison

  thContent: "Inherits from"
  detail: "parents"

  detailParts: (pathModel) -> [ textElem('code', pathModel.get('path')) ]

class ViewComparison extends DetailComparison

  thContent: "selected path"
  detail: 'select'

  detailParts: (pathModel) -> [
      textElem('code', pathModel.get('path'), className: 'selected-path')
  ]

class ConstraintComparison extends DetailComparison

  thContent: "constraint"
  detail: "where"

  detailParts: (constraintModel) ->
    {path, op, type, switched, editable} = constraintModel.toJSON()
    parts = [
      textElem('code', path, className: 'constrained-path'),
      textElem('span', " "),
      textElem('code', (op or type), className: 'constraint-operator'),
      textElem('span', " "),
      textElem('span', (if op? then "?" else ''))
    ]
    if switched?
      parts = parts.concat( [
        textElem('span', ' '), textElem('code', switched)
      ])

    if editable?
      parts = parts.concat( [
        textElem('span', ' '), textElem('code', (if editable then "editable" else "hidden"))
      ])

    parts


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
