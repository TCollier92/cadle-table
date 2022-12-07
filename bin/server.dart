import 'dart:convert';
import 'dart:io';

import 'package:html/dom.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart';
import 'package:shelf_cors_headers/shelf_cors_headers.dart';
import 'package:shelf_router/shelf_router.dart';
import 'package:path/path.dart' as p;
import 'package:shelf_virtual_directory/shelf_virtual_directory.dart';
import 'package:http/http.dart' as http;
import 'package:html/parser.dart';

final fsPath = p.join(Directory.current.path, 'web');

DateTime d1CacheTime = DateTime.utc(2000);
List<LeagueRow> d1Cache = [];
DateTime d2CacheTime = DateTime.utc(2000);
List<LeagueRow> d2Cache = [];

// Configure routes.
final _router = Router()
  ..get('/echo/<message>', _echoHandler)
  ..get('/yahoo/table', _tableHandler)
  ..get('/yahoo/table2', _tableHandler2)
  ..mount('/', ShelfVirtualDirectory(fsPath).router);

Response _echoHandler(Request request) {
  final message = request.params['message'];
  return Response.ok('$message\n');
}

Future<Response> _tableHandler(Request request) async {
  return _getTable(1);
}

Future<Response> _tableHandler2(Request request) async {
  return _getTable(2);
}

Future<Response> _getTable(int division) async {
  var cacheTime = division == 1 ? d1CacheTime : d2CacheTime;

  if (cacheTime.isAfter(DateTime.now().add(Duration(seconds: -15)))) {
    return Response.ok(jsonEncode(division == 1 ? d1Cache : d2Cache),
        headers: {"Content-Type": "application/json"});
  }

  final Uri url = Uri.parse(division == 1
      ? "https://football.fantasysports.yahoo.com/league/cadlefantasyleague"
      : "https://football.fantasysports.yahoo.com/league/cadlefantasyleaguedivision2");
  final response = await http.get(url);
  final document = parse(response.body);
  final matchupElements =
      document.querySelectorAll("#matchupweek .List-rich li .Grid-h-mid");
  final matchupObjects = matchupElements.map((e) => _parseMatchupRow(e));

  final leagueRowElements =
      document.querySelectorAll("#standingstable tbody tr");
  final leagueRowObjects = leagueRowElements.map((e) => _parseLeagueRow(e));

  final updatedLeagueTable =
      _getFullLeagueTable(matchupObjects.toList(), leagueRowObjects.toList());

  updatedLeagueTable.sort();

  if (division == 1) {
    d1Cache = updatedLeagueTable;
    d1CacheTime = DateTime.now();
  } else {
    d2Cache = updatedLeagueTable;
    d2CacheTime = DateTime.now();
  }

  return Response.ok(jsonEncode(updatedLeagueTable),
      headers: {"Content-Type": "application/json"});
}

class Matchup {
  final String name;
  final int score;

  Matchup(this.name, this.score);
}

class LeagueRow implements Comparable {
  final String name;
  final int startingPosition;
  final int wins;
  final int losses;
  final int ties;
  final int pointsFor;
  final int pointsAgainst;
  final String imgUrl;

  LeagueRow(
    this.name,
    this.startingPosition,
    this.wins,
    this.losses,
    this.ties,
    this.pointsFor,
    this.pointsAgainst,
    this.imgUrl,
  );

  @override
  int compareTo(other) {
    final casted = other as LeagueRow;
    int winDiff = casted.wins - wins;
    if (winDiff != 0) return winDiff;
    int lossDiff = losses - casted.losses;
    if (lossDiff != 0) return lossDiff;
    int pfDiff = casted.pointsFor - pointsFor;
    if (pfDiff != 0) return pfDiff;
    return 0;
  }

  LeagueRow.fromJson(Map<String, dynamic> json)
      : name = json["name"],
        startingPosition = json["startingPosition"],
        wins = json['wins'],
        losses = json['losses'],
        ties = json['ties'],
        pointsFor = json['pointsFor'],
        pointsAgainst = json['pointsAgainst'],
        imgUrl = json['imgUrl'];

  Map<String, dynamic> toJson() => {
        'name': name,
        'startingPosition': startingPosition,
        'wins': wins,
        'losses': losses,
        'ties': ties,
        'pointsFor': pointsFor,
        'pointsAgainst': pointsAgainst,
        'imgUrl': imgUrl
      };
}

Matchup _parseMatchupRow(Element e) {
  return Matchup(
    e.querySelector(".F-link")?.innerHtml ?? "",
    int.parse(e.querySelector(".F-shade")?.innerHtml ?? "1"),
  );
}

LeagueRow _parseLeagueRow(Element e) {
  var wltList = e.children[2].innerHtml.split('-');
  return LeagueRow(
    e.children[1].children[1].innerHtml,
    int.parse(e.children[0].children[1].innerHtml.replaceAll("*", "")),
    int.parse(wltList[0]),
    int.parse(wltList[1]),
    int.parse(wltList[2]),
    int.parse(e.children[3].innerHtml),
    int.parse(e.children[4].innerHtml),
    e.children[1].children[0].children[0].attributes["src"] ?? "",
  );
}

List<LeagueRow> _getFullLeagueTable(
    List<Matchup> matchupElements, List<LeagueRow> leagueRows) {
  final List<LeagueRow> output = [];

  for (int i = 0; i < matchupElements.length; i += 2) {
    bool t1Win = matchupElements[i].score > matchupElements[i + 1].score;
    bool t1Loss = matchupElements[i].score < matchupElements[i + 1].score;
    bool t1Tie = !t1Win && !t1Loss;
    bool t2Win = t1Loss;
    bool t2Loss = t1Win;
    bool t2Tie = t1Tie;
    int t1Score = matchupElements[i].score;
    int t2Score = matchupElements[i + 1].score;

    LeagueRow t1 =
        leagueRows.firstWhere((lr) => lr.name == matchupElements[i].name);
    LeagueRow t2 =
        leagueRows.firstWhere((lr) => lr.name == matchupElements[i + 1].name);

    LeagueRow updatedT1 = LeagueRow(
      t1.name,
      t1.startingPosition,
      t1.wins + (t1Win ? 1 : 0),
      t1.losses + (t1Loss ? 1 : 0),
      t1.ties + (t1Tie ? 1 : 0),
      t1.pointsFor + t1Score,
      t1.pointsAgainst + t2Score,
      t1.imgUrl,
    );
    LeagueRow updatedT2 = LeagueRow(
      t2.name,
      t2.startingPosition,
      t2.wins + (t2Win ? 1 : 0),
      t2.losses + (t2Loss ? 1 : 0),
      t2.ties + (t2Tie ? 1 : 0),
      t2.pointsFor + t2Score,
      t2.pointsAgainst + t1Score,
      t2.imgUrl,
    );
    output.add(updatedT1);
    output.add(updatedT2);
  }

  return output;
}

void main(List<String> args) async {
  // Use any available host or container IP (usually `0.0.0.0`).
  final ip = InternetAddress.anyIPv4;

  final overrideHeaders = {
    ACCESS_CONTROL_ALLOW_ORIGIN: '*',
    'Content-Type': 'application/json;charset=utf-8'
  };

  // Configure a pipeline that logs requests.
  final _handler = Pipeline()
      .addMiddleware(logRequests())
      .addMiddleware(corsHeaders(headers: overrideHeaders))
      .addHandler(_router);

  // For running in containers, we respect the PORT environment variable.
  final port = int.parse(Platform.environment['PORT'] ?? '8080');
  final server = await serve(_handler, ip, port);
  print('Server listening on port ${server.port}');
}
