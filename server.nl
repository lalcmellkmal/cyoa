var config = require('./config'),
    http = require('http'),
    fs = require('fs'),
    universe = require('./universe');

function plural(word, count) {
    return parseInt(count, 10) == 1 ? word : word + 's';
}

var world = new universe.World(1);

var Nope = universe.Nope;

function setup(cb) {
    count <- world.getRoomCount();
    if (!count) {
        id <- world.createRoom({vis: {desc: "You are at home."}});
        _ <- world.setStartingRoom(id);
        return "Made initial room.";
    }
    else {
        return "World has " + count + " " + plural('room', count);
    }
}

setup(function (err, msg) {
    if (err) throw err;
    console.log(msg);
});

var dirOpposites = {north: 'south', south: 'north', west: 'east', east: 'west', up: 'down', down: 'up'};

function execute(query, player, cb) {
    switch (query.verb) {
        case 'go':
        {
            var dir = query.arg.dir;
            oldLoc <- player.getLoc();
            newLoc <- world.lookupRoomExit(oldLoc, query.arg.dir);
            if (!newLoc)
                return Nope("Can't go that way.");
            _ <- player.move(oldLoc, newLoc, query.arg.dir);
            newRoom <- world.getRoom(newLoc);
            return look(newRoom);
        }

        case 'dig':
        {
            var dir = query.arg.dir, backDir = dirOpposites[dir];
            if (!dir || !backDir)
                return Nope("That's not a direction.");
            oldId <- player.getLoc();
            _ <- world.addRoomExit(oldId, dir);
            newId <- world.createRoom({});
            _ <- world.setRoomExit(newId, backDir, oldId);
            _ <- world.setRoomExit(oldId, dir, newId);
            _ <- player.move(oldId, newId, dir);
            room <- world.getRoom(newId);
            var msg = look(room);
            msg.prefix = 'Dug.';
            return msg;
        }

        case 'desc':
        {
            var newDesc = query.arg.desc.slice(0, 140);
            loc <- player.getLoc();
            room <- world.getRoom(loc);
            if (!room.vis)
                room.vis = {};
            room.vis.desc = newDesc;
            _ <- world.updateRoom(loc, 'vis', room.vis);
            var msg = look(room);
            msg.prefix = 'Changed.'
            return msg;
        }

        case 'look':
        {
            room <- player.getRoom();
            return look(room);
        }
 
        default:
            cb(null, "What?");
    }
}

function look(room) {
    var vis = {};
    vis.msg = (room.vis && room.vis.desc) || "Can't see shit captain.";
    if (room.exits)
        vis.exits = Object.keys(room.exits);
    if (room.players)
        vis.msg += ' Players: ' + room.players;
    return vis;
}

function doCommand(player, command, callback) {
    if (typeof command != 'object')
        return callback("Bad command.");

    try {
        execute(command, player, function (err, msg) {
            if (err) {
                if (err instanceof Nope)
                    return callback(err.message);
                dumpError(err, command, player);
                return callback('Game error.');
            }
            if (msg instanceof Nope)
                return callback(msg.message);
            if (typeof msg == 'string')
                msg = {msg: msg};
            callback(null, msg);
        });
    }
    catch (e) {
        dumpError(e, command, player);
        callback('Server error.');
    }
}

function dumpError(error, command, player) {
    console.error((player ? 'Player #' + player.id : 'Unknown player') + " using command:");
    console.error(JSON.stringify(command));
    console.error("caused error:");
    console.error(error.stack || error);
}

/* WEB STUFF */

function handler(req, resp) {
    // TEMP debug
    if (config.DEBUG) {
        var name = req.url.slice(1);
        if (name == '') {
            resp.writeHead(200, {'Content-Type': 'text/html; charset=UTF-8'});
            fs.readFile('index.html', function (err, html) {
                if (err) throw err;
                resp.end(html);
            });
            return;
        }
        else if (media.indexOf(name) >= 0) {
            var mime = name.match(/\.js$/) ? 'application/javascript' : 'text/css';
            resp.writeHead(200, {'Content-Type': mime});
            var filename = req.url.slice(1);
            if (filename == 'client.js')
                filename = 'out/client.js';
            fs.readFile(filename, function (err, data) {
                if (err) throw err;
                resp.end(data);
            });
            return;
        }
        else {
            console.warn('No /' + name);
        }
    }
    resp.writeHead(404);
    resp.end('Not found');
}

var media = ['client.js', 'plain.css', 'jquery-1.7.1.min.js', 'sockjs-0.3.1.min.js', 'input.js'];

var server = http.createServer(handler);
server.listen(config.PORT);

var sockJs = require('sockjs').createServer({
    sockjs_url: 'sockjs-0.3.1.min.js',
    prefix: '/sock',
    jsessionid: false,
});
server.on('upgrade', function (req, resp) {
    resp.end();
});
sockJs.installHandlers(server);

var CLIENTS = {};

function Client(id) {
    this.clientId = id;
    this.commandResult = this.onCommandResult.bind(this);
};

Client.prototype.emit = function (name, arg) {
    this.socket.write(JSON.stringify({e: name, a: arg}));
};

Client.prototype.onClose = function () {
    if (CLIENTS[this.clientId] === this)
        delete CLIENTS[this.clientId];
};

Client.prototype.onCommand = function (data) {
    var command;
    try {
        command = JSON.parse(data);
    }
    catch (e) {}
    if (!command)
        return this.emit('error', 'Invalid command.');
    doCommand(this.player, command, this.commandResult);
};

Client.prototype.onCommandResult = function (err, result) {
    if (err)
        this.emit('error', err);
    else
        this.emit('result', result);
};

function onLogin(id) {
    if (!id.match(/^\d{1,20}$/))
        return this.write(JSON.stringify({e: 'error', a: 'Bad id.'}));
    var client = CLIENTS[id];
    if (!client)
        CLIENTS[id] = client = new Client(id);
    if (client.socket) {
        client.emit('error', 'Kicked out by another browser session.');
        client.socket.close();
    }
    client.socket = this;
    client.socket.on('close', client.onClose.bind(client));

    if (!client.player) {
        universe.Player.getOrCreate(id, world, function (err, player) {
            if (err) {
                console.error(err);
                client.emit('error', "Couldn't enter world.");
            }
            else if (client.player) {
                // Shouldn't happen due to .once()
                client.emit('error', 'Login conflict.');
            }
            else {
                client.player = player;
                ready('Welcome, ' + player.name + '.');
            }
        });
    }
    else
        ready('Welcome back, ' + client.player.name + '.');

    function ready(welcome) {
        client.emit('login', {msg: welcome});
        client.socket.on('data', client.onCommand.bind(client));
    }
}

sockJs.on('connection', function (socket) {
    socket.once('data', onLogin.bind(socket));
});

// vi: set sw=4 ts=4 sts=4 ai et filetype=javascript:
