fs    = require 'fs'
path  = require 'path'
knox  = require 'knox'
async = require 'async'

module.exports = class CloudFrontBrunch
  brunchPlugin: yes

  constructor: (@config) ->
    awsAccess = process.env['AWS_ACCESS_KEY_ID']
    awsSecret = process.env['AWS_SECRET_ACCESS_KEY']
    unless awsAccess && awsSecret
      console.log "Please setup AWS_ACCESS_KEY_ID and AWS_SECRET_ACCESS_KEY with your aws credentials."
      return

    @options = @config.plugins.cloudfront || @config.cloudfront
    unless @options?.bucket?
      console.log "Please configure the s3 bucket to upload to."
      return

    @s3 = knox.createClient
      key   : awsAccess
      secret: awsSecret
      bucket: @options.bucket

  # TODO gzip
  onCompile: ->
    version = Math.floor(Date.now()/1000)
    root    = if @options.local then '' else (@options.cdnUrl+'/'+version)

    readDir @config.paths.public, (err, dir) =>
      async.each dir.files, (f, cb) =>
        replaceInFile f, '//\\$CDN', root, (err) =>
          return console.log(err) if err
          return cb() if @options.local

          @s3.putFile f, "/#{version}/#{f.substring(7)}", (err, res) ->
            console.log err if err
            res.resume()
            cb(err)
      , (err) =>
        console.log err if err

replaceInFile = (f, token, replacement, cb) ->
  return cb() unless /\.(html|css)$/.test(f)
  fs.readFile f, (err, data) ->
    return cb(err) if err
    result = data.toString().replace(new RegExp(token, 'g'), replacement)
    fs.writeFile f, result, (err) ->
      console.log(err) if err
      cb(err)

readDir = (start, cb) ->
  # Use lstat to resolve symlink if we are passed a symlink
  fs.lstat start, (err, stat) ->
    return callback(err) if err

    found = {dirs: [], files: []}
    total = processed = 0
    isDir = (abspath) ->
      fs.stat abspath, (err, stat) ->
        if stat.isDirectory()
          found.dirs.push(abspath)
          # If we found a directory, recurse!
          readDir abspath, (err, data) ->
            found.dirs  = found.dirs.concat(data.dirs)
            found.files = found.files.concat(data.files)
            if ++processed == total
              cb null, found
        else
          found.files.push(abspath)
          if ++processed == total
            cb null, found

    # Read through all the files in this directory
    if stat.isDirectory()
      fs.readdir start, (err, files) ->
        total = files.length
        for f in files
          isDir(path.join(start, f))
    else
      return cb(new Error("path: " + start + " is not a directory"))
