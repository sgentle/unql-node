readline = require 'readline'
request  = require 'request'
burrito  = require 'burrito'
prompt   = require 'prompt'
util     = require 'util'
url      = require 'url'

pp = (x) -> util.inspect x, no, 2, (not (process.platform is 'win32' or process.env.NODE_DISABLE_COLORS))

opts = require('optimist')
    .usage('Usage: $0 [options] [couchURL (default http://localhost:5984)]')
    .options
      u: alias: 'user', describe: 'Database user'
      p: alias: 'password', describe: 'Database password (will prompt if omitted)'
      h: alias: 'help', describe: "Show this message"

argv = opts.argv

return console.log opts.help() if argv.help

if argv._[0]
  couchURL = argv._[0].replace /\/$/, ''
  couchURL = "http://#{couchURL}" unless couchURL.match "://"
else
  couchURL = "http://localhost:5984"

# Set auth header via command line switch or prompt if needed
couchAuth = null

if argv.user
  if argv.password
    couchAuth = "Basic " + new Buffer("#{argv.user}:#{argv.password}").toString 'base64'
    process.nextTick -> start()
  else
    prompt.start()
    prompt.get name: 'password', hidden: true, (err, result) ->
      if err
        console.log "Prompt error ", err
      else
        couchAuth = "Basic " + new Buffer("#{argv.user}:#{result.password}").toString 'base64'

        start()
else
  process.nextTick -> start()

###
# Actual REPL code
###

rl = null
start = ->
  rl = readline.createInterface process.stdin, process.stdout, null
  rl.setPrompt "#{url.parse(couchURL).hostname}> "
  rl.prompt()

  rl.on 'line', (line) ->
    waiting = true
    processExpr line, (err, result) ->
      waiting = false
      if err
        if typeof err is 'string'
          console.log pp {error: err}
        else
          console.log pp err
      else
        console.log pp result
    
      rl.prompt()

    console.log "..." if waiting



###
# Regex matching stuff
# Each user command is matched in order against the regexes specified with 'handle'
# Regexes are case insensitive by default, and anchored to the start and end of the command
###

matchers = []
handlers = []

handle = (match, fn) ->
  match = new RegExp "^#{match.source}$", 'i'
  
  matchers.push match
  handlers.push fn

processExpr = (expr, cb) ->
  matched = false
  for matcher, i in matchers
    if match = expr.match matcher
      args = (x for x, j in match when j isnt 0)
      handlers[i] args..., cb
      matched = true
      break
  
  cb "No such command" unless matched




###
# Helper methods for accessing CouchDB
###

makeURL = (db, doc='') ->
  db = db.replace /\/$/, ''
  if db.match "://"
    "#{db}/#{doc}"
  else
    "#{couchURL}/#{db}/#{doc}"


couchreq = (method, db, doc, data, cb) ->
  [doc, data, cb] = [null, doc, data] if cb is undefined

  url = makeURL(db, doc)
  headers = if couchAuth and not db.match "://" then {Authorization: couchAuth} else {}

  req = 
    method: method
    uri: makeURL db, doc
    headers: headers
    json: data

  request req, (err, req, body) ->
    if err
      cb err
    else if body.error
      cb body
    else      
      cb null, body, req

couchreq.get = (args...) -> couchreq 'GET', args...
couchreq.put = (args...) -> couchreq 'PUT', args...
couchreq.post = (args...) -> couchreq 'POST', args...
couchreq.delete = (args...) -> couchreq 'DELETE', args...

select = (db, expr, errcb, cb) ->
  data = map: "function(doc){with(doc){if(#{expr}){emit(null, doc);}}}"
  couchreq.post db, '_temp_view', data, (err, body) ->
    if err then errcb err else cb body.rows




###
# Actual handlers
###

handle /quit/, ->
  rl.close()
  process.stdin.destroy() 

handle /insert into (\S+) value (.*)/, (db, expr, cb) ->
  try
    expr = do -> eval "(#{expr})"
  catch e
    cb "expression isn't valid JSON"
    return

  couchreq.post db, expr, cb

handle /insert into (\S+) select (.*)/, (db, selectExpr, cb) ->
  processExpr "select " + selectExpr, (err, docs) ->
    if err
      cb err
    else
      couchreq.post db, '_bulk_docs', {docs}, cb

handle /select (.*? )?from (\S+)(?: where (.*))?/, (outexpr, db, expr=true, cb) ->
  select db, expr, cb, (rows) ->
    results = []
    for {value: row} in rows
      result = null
      if outexpr
        # Hey, look, I'm Coffeescript! I'm too good to support 'with' because nobody will ever need that except when they do.
        # Mind the sharp edges, kids, we're putting the safety scissors away so we can get some real work done.
        try
          `with(row){result = (function(){return eval("("+outexpr+")");})()}`
        catch e
          cb e.message
          return

        null
      else
        result = row
      results.push result #JSON.stringify result
    
    cb null, results#.join "\n"

handle /update (\S+) set (.*?)(?: where (.*))?/, (db, updateExpr, expr=true, cb) ->  
  updateExpr = "var #{updateExpr}"
  burrito updateExpr, (node) ->
    if node.name is 'var'
      vars = node.label()
      select db, expr, cb, (rows) ->
        updates = []
        for {value: row} in rows
          row[v] = null for v in vars
          try
            `(function(){with(row){eval(updateExpr);}})()`
          catch e
            cb "bad update expression: #{e.message}"
            return
          updates.push row

        couchreq.post db, '_bulk_docs', {docs: updates}, cb

handle /delete from (\S+)(?: where (.*))?/, (db, expr, cb) ->
  query = "update #{db} set _deleted = true"
  query += " where #{expr}" if expr
  processExpr query, cb

handle /create collection (\S+)/, (db, cb) ->
  couchreq.put db, {}, cb

handle /drop collection (\S+)/, (db, cb) ->
  couchreq.delete db, {}, cb

handle /show collections/, (cb) ->
  couchreq.get '_all_dbs', {}, cb

handle /use (\S+)/, (newurl,cb) ->
  couchURL = newurl.replace /\/$/, ''
  couchURL = "http://#{couchURL}" unless couchURL.match "://"

  rl.setPrompt "#{url.parse(couchURL).hostname}> "
  couchAuth = null
  cb null, ok: true

handle /select (.*)/, (expr, cb) ->
  try
    cb null, do -> eval "(#{expr})"
    null
  catch e
    cb e.message


handle /help/, (cb) ->
  cb null, "Available commands": [
    "select EXPRESSION"
    "select from COLLECTION"
    "select from COLLECTION where CONDITION"
    "select EXPRESSION from COLLECTION"
    "select EXPRESSION from COLLECTION where CONDITION"
    "insert into COLLECTION value DATA"
    "insert into COLLECTION select ..."
    "update COLLECTION set KEY=VAL,KEY2=VAL2"
    "update COLLECTION set KEY=VAL,KEY2=VAL2 where CONDITION"
    "delete from COLLECTION"
    "delete from COLLECTION where CONDITION"
    "create collection COLLECTION"
    "drop collection COLLECTION"
    "show collections"
    "use URL"
    "quit"
    "help"
  ]
