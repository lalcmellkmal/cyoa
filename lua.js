var crypto = require('crypto');

var db;

exports.setDb = function (newDb) {
	db = newDb;
};

function LuaScript(src) {
	if (!(this instanceof LuaScript))
		return new LuaScript(src);
	this.src = this.convertLookups(this.transformSource(src));
	this.sha = crypto.createHash('sha1').update(src).digest('hex');
}
exports.LuaScript = LuaScript;

LuaScript.prototype.transformSource = function (src) {
	this.modifiers = {};
	var keyCount = 0, argCount = 0;
	var result = [];
	var bits = src.split(/(KEYS|ARGV|JSONHASH)\[(\d+)\]/g);
	for (var i = 0; i < bits.length; i++) {
		if (i % 3 == 0) {
			result.push(bits[i]);
			continue;
		}
		var kind = bits[i];
		var index = parseInt(bits[++i], 10);
		var transformed = null;
		if (kind == 'KEYS')
			keyCount = Math.max(keyCount, index);
		else {
			argCount = Math.max(argCount, index);
			if (kind == 'JSONHASH') {
				transformed = 'unpack(cjson.decode(ARGV[' + index + ']))';
				this.modifiers[index] = stringifyValues;
			}
		}
		result.push(transformed || (kind + '[' + index + ']'));
	}
	this.keyCount = keyCount;
	this.argCount = argCount;
	src = result.join('');
	src = src.replace(/DEBUG\(/g, 'redis.log(redis.LOG_WARNING, ');
	return src;
};

LuaScript.prototype.convertLookups = function (src) {
	this.extraKeys = [];
	this.extraArgs = [];
	var keyIndices = {}, argIndices = {};
	var result = [];
	var bits = src.split(/([KA])\[([\w:]+)\]/g);
	for (var i = 0; i < bits.length; i++) {
		if (i % 3 == 0) {
			result.push(bits[i]);
			continue;
		}
		var kind = bits[i];
		var fullKey = bits[++i];

		var transformed;
		if (kind == 'K') {
			var index = keyIndices[fullKey];
			if (!index) {
				var parts = fullKey.match(/^(\w+)(:.+)?$/);
				var info = {stem: parts[1], tail: parts[2] || ''};
				var m = info.stem.match(/[A-Z][a-z]*$/);
				info.noun = m ? m[0].toLowerCase() : info.stem;
				this.extraKeys.push(info);
				var index = this.keyCount + this.extraKeys.length;
				keyIndices[fullKey] = index;
			}
			transformed = 'KEYS[' + index + ']';
		}
		else if (kind == 'A') {
			var index = argIndices[fullKey];
			if (!index) {
				this.extraArgs.push(fullKey);
				var index = this.argCount + this.extraArgs.length;
				argIndices[fullKey] = index;
			}
			transformed = 'ARGV[' + index + ']';
		}
		result.push(transformed);
	}
	return result.join('');
};

LuaScript.prototype.eval = function (keywords, keys, args, callback) {
	if (!callback) {
		callback = args;
		args = [];
	}
	if (!callback) {
		callback = keys;
		keys = [];
	}
	var self = this;

	var n = this.keyCount;
	if (keys.length != n)
		throw "Ought to have " + n + " key(s): " + keys;
	if (args.length != this.argCount)
		throw "Ought to have " + this.argCount + " arg(s): " + args;

	/* Insert keyword arguments */
	var allArgs = keys.slice();
	n += this.extraKeys.length;
	this.extraKeys.forEach(function (keyInfo) {
		if (!(keyInfo.stem in keywords))
			throw "Keyword missing: " + keyInfo.stem;
		allArgs.push(keyInfo.noun + ':' + keywords[keyInfo.stem] + keyInfo.tail);
	});
	/* Massage values according to previous spec */
	args.forEach(function (val, i) {
		var func = self.modifiers[i + 1];
		allArgs.push((func ? func(val) : val).toString());
	});
	this.extraArgs.forEach(function (keyword) {
		if (!(keyword in keywords))
			throw "Argument missing: " + keyword;
		allArgs.push(keywords[keyword].toString());
	});

	db.evalsha(this.sha, n, allArgs.slice(), function (err, result) {
		/* Gah, this sucks. Any way to get the redis error name? */
		if (err && err.message.match(/NOSCRIPT/))
			db.eval(self.src, n, allArgs, callback);
		else if (err)
			callback(err);
		else
			callback(null, result);
	});
};

function stringifyValues(obj) {
	var results = [];
	for (var k in obj)
		results.push(k, JSON.stringify(obj[k]));
	return JSON.stringify(results);
}
