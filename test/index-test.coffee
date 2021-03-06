expect     = require 'expect.js'
path       = require 'path'
cheerio    = require 'cheerio'
_          = require 'lodash'
fs         = require 'fs-extra'
tmp        = require 'tmp'

staticI18n = require '../src/index'

describe 'processor', ->
  basepath = path.join __dirname, 'data'

  file = path.join basepath, 'index.html'
  options = {}

  beforeEach ->
    options = {localesPath: path.join(__dirname, 'data', 'locales'), outputDir: false}

  describe '#process', ->
    input = '<p data-t="foo.bar"></p>'

    it 'should process all locales', (done) ->
      _.merge options, {locales: ['en', 'ja']}
      staticI18n.process input, options, (err, results) ->
        expect(results).to.only.have.keys ['ja', 'en']
        expect(results.ja).to.be '<p>ja_bar</p>'
        expect(results.en).to.be '<p>bar</p>'
        done()

    it 'should work with yaml', (done) ->
      input = '<p data-t="yaml.bar"></p>'
      _.merge options, {fileFormat: 'yml'}
      staticI18n.process input, options, (err, results) ->
        expect(results).to.only.have.keys ['en']
        expect(results.en).to.be '<p>bar</p>'
        done()

    it 'should translate attributes', (done) ->
      input = '<input class="foo" id="ok" data-attr-t value-t="foo.bar">'
      staticI18n.process input, options, (err, results) ->
        expect(results).to.only.have.keys ['en']
        $ = cheerio.load(results.en)
        expect($('input').attr('value')).to.be 'bar'
        expect($('input').attr('id')).to.be 'ok'
        done()

  describe '#processFile', ->
    it 'should translate data-t', (done) ->
      staticI18n.processFile file, options, (err, results) ->
        $ = cheerio.load(results.en)
        expect($('#bar').text()).to.be 'bar'
        done()

    it 'should translate data-t content', (done) ->
      staticI18n.processFile file, options, (err, results) ->
        $ = cheerio.load(results.en)
        expect($('#baz').text()).to.be 'baz'
        expect($('#bar-replace > span').text()).to.be 'bar'
        done()

    it 'should replace', (done) ->
      options = _.defaults {replace: true}, options
      staticI18n.processFile file, options, (err, results) ->
        $ = cheerio.load(results.en)
        expect($('#bar').length).to.be 0
        expect($('#baz').length).to.be 0
        expect($('#bar-replace').html()).to.be 'bar'
        done()

    it 'should work with other selectors', (done) ->
      options = _.defaults {replace: true, selector: 't'}, options
      staticI18n.processFile file, options, (err, results) ->
        $ = cheerio.load(results.en)
        expect($('#bar-replace-sel').html()).to.be 'bar'
        done()

    it 'should translate conditional comments', (done) ->
      options = _.defaults {translateConditionalComments: true}, options
      staticI18n.processFile file, options, (err, results) ->
        $ = cheerio.load(results.en)
        html = $.html()
        expect(html.indexOf('data-attr-t')).to.be -1
        _.each [6, 7, 8], (n) ->
          expect(html.indexOf("class=\"ie ie#{n}\" lang=\"bar\"")).not.to.be -1
        expect(html.indexOf('You are using')).not.to.be -1
        done()



  describe '#processDir', ->
    it 'should process all files', (done) ->
      _.merge options, {locales: ['en', 'ja'], exclude: ['ignored/']}
      staticI18n.processDir basepath, options, (err, results) ->
        expect(results).to.only.have.keys ['index.html', 'other.html', 'sub/index.html']
        expect(results['index.html']).to.only.have.keys ['en', 'ja']
        expect(results['other.html']).to.only.have.keys ['en', 'ja']
        $ = cheerio.load(results['index.html'].en)
        expect($('#bar').text()).to.be 'bar'
        done()

  describe 'withOutput', ->
    dir = cleanup = null

    beforeEach (done) ->
      tmp.dir {unsafeCleanup: true}, (err, path, cleanupCb) ->
        dir = path
        _.extend options, {outputDir: dir, locales: ['en', 'ja']}
        cleanup = cleanupCb
        done()

    afterEach ->
      cleanup()

    it 'should write all files', (done) ->
      staticI18n.processDir basepath, options, (err, results) ->
        files = fs.readdirSync dir
        _.each ['index.html', 'other.html', 'ja', 'sub'], (f) -> expect(files).to.contain(f)
        files = fs.readdirSync path.join(dir, 'ja')
        _.each ['index.html', 'other.html', 'sub'], (f) -> expect(files).to.contain(f)
        $ = cheerio.load fs.readFileSync(path.join(dir, 'index.html'), 'utf8')
        expect($('#bar').text()).to.be 'bar'
        $ = cheerio.load fs.readFileSync(path.join(dir, 'sub', 'index.html'), 'utf8')
        expect($('#bar').text()).to.be 'bar'
        done()

    it 'should handle overrides', (done) ->
      _.extend options, {outputOverride: {en: {'index.html': 'foo.html'}}}
      staticI18n.processDir basepath, options, (err, results) ->
        files = fs.readdirSync dir
        _.each ['foo.html', 'other.html', 'ja'], (f) -> expect(files).to.contain(f)
        expect(files).to.not.contain 'index.html'
        done()

    it 'should fix pathes', (done) ->
      staticI18n.processDir basepath, options, (err, results) ->
        $ = cheerio.load fs.readFileSync(path.join(dir, 'ja', 'index.html'), 'utf8')
        expect($('#rel-script').attr('src')).to.be '../foo.js'
        expect($('#abs-script').attr('src')).to.be '//foo.js'
        expect($('#rel-link').attr('href')).to.be '../foo.css'
        expect($('#abs-link').attr('href')).to.be '//foo.css'
        $ = cheerio.load fs.readFileSync(path.join(dir, 'index.html'), 'utf8')
        expect($('#rel-script').attr('src')).to.be 'foo.js'
        expect($('#rel-link').attr('href')).to.be 'foo.css'
        done()
