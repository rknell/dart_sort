/// A script that will sort files in the download directory into the correct
/// directories in the media directory.
///
/// It will also rename the files to the correct format.
/// It will also delete any files that are not video files.
/// It will also delete any empty directories in the download directory.
/// It will also delete any empty directories in the media directory.
/// It will also delete any directories that are empty after moving the file.
///

import 'dart:async';
import 'dart:io';

/// Video extensions that will be moved
const videoExtensions = ['mkv', 'avi', 'mp4', 'm4v'];

/// Files that will be deleted
const ignoreFiles = ['nzb', 'nfo', 'srr'];

/// The main function that will run the script
main() async {
  print('Starting script');
  runner();
}

/// A function that will run sortTV() and sortMovies() continuously but never at the same time.
/// It should recover after any failures
/// It will also run the initial sort
void runner() async {
  //Run the initial sort
  var lastRun = DateTime.now().subtract(Duration(minutes: 10));

  //Run the sort every 30 seconds
  while (true) {
    try {
      //Check if the last run was more than 5 minutes ago
      if (lastRun.isBefore(DateTime.now().subtract(Duration(minutes: 5)))) {
        try {
          await Future.wait([sortTV(), sortMovies()]);
        } catch (e, s) {
          print('Error sorting');
          print(e);
          print(s);
        } finally {
          //Update the last run time
          lastRun = DateTime.now();
        }
        print('Finished sorting ${lastRun.toIso8601String()}');
      }
    } catch (e, s) {
      print(e);
      print(s);
    }

    //Wait 30 seconds

    await Future.delayed(Duration(seconds: 30));
  }
}

/// A function that will sort tv shows into their correct directory
///
Future sortTV() {
  //Sort the tv shows
  return _sort(
      downloadDir: Directory('/mnt/media/downloads/completed/Series'),
      destinationDir: Directory('/mnt/media/tv'),
      nameParser: (name) {
        print('Parsing $name');

        //Parse the filename
        final regex =
            RegExp(r'(.+)S([0-9]{2})E([0-9]{2})', caseSensitive: false);

        //Get the match
        final matchRegexp = regex.allMatches(name);

        //Check if there is a match
        if (matchRegexp.isEmpty) {
          throw Exception('No match found for $name');
        }

        final match = matchRegexp.first;

        //Get the series name, season and episode
        final seriesName = match.group(1)?.replaceAll('.', ' ').trim();
        final season = match.group(2);
        final episode = match.group(3);

        //Return the result
        return NameParserResult(
            targetDir: "${seriesName}/Season ${season}",
            targetFileName: "${seriesName} S${season}E${episode}");
      });
}

/// A function that will sort movies into their correct directory
Future sortMovies() {
  //Sort the movies
  return _sort(
      downloadDir: Directory('/mnt/media/downloads/completed/Movies'),
      destinationDir: Directory('/mnt/media/movies'),
      nameParser: (name) {
        //Parse the filename
        final regex = RegExp(r'(.+)\.([0-9]{4})\.', caseSensitive: false);
        final match = regex.allMatches(name).first;

        //Get the movie name and year
        final movieName = match.group(1)?.replaceAll('.', ' ').trim();
        final year = match.group(2);

        //Return the result
        return NameParserResult(targetFileName: "${movieName} ${year}");
      });
}

/// A function that will sort files in the download directory into the correct
/// directories in the media directory.
///
/// It will also rename the files to the correct format.
/// It will also delete any files that are not video files.
/// It will also delete any empty directories in the download directory.
/// It will also delete any empty directories in the media directory.
/// It will also delete any directories that are empty after moving the file.
Future _sort({
  required Directory downloadDir,
  required Directory destinationDir,
  required NameParserResult Function(String name) nameParser,
}) async {
  await for (var download in downloadDir.list()) {
    //Get the final name of the file
    final name =
        download.uri.pathSegments.where((element) => element.isNotEmpty).last;

    print('Processing $name');

    //Check if the file is a directory
    final stat = await download.stat();
    if (stat.type == FileSystemEntityType.directory) {
      //Get the contents of the directory
      final sourceDirectory = Directory(download.path);
      final sourceDirectoryContents = await sourceDirectory.list().toList()
        ..sort(((a, b) {
          // Sort by size descending
          return b.statSync().size.compareTo(a.statSync().size);
        }));

      //Loop through the contents of the directory
      for (var file in sourceDirectoryContents) {
        final itemStat = await file.stat();

        //Check if the item is a file
        if (itemStat.type == FileSystemEntityType.file) {
          final filename = file.uri.pathSegments.last;

          //Check if the file is a video file
          final extensionSplit = filename.split('.');
          if (extensionSplit.length >= 2) {
            final extension = extensionSplit.last;

            //Check if the files extension is a video extension
            for (var videoExtension in videoExtensions) {
              if (extension.toLowerCase() == videoExtension.toLowerCase()) {
                //Move and rename
                late NameParserResult paths;
                try {
                  paths = nameParser(name);
                } catch (e, s) {
                  print("Error parsing path $name");
                  print(e);
                  print(s);
                  continue;
                }

                //Create the target directory
                var targetDir = Directory("${destinationDir.path}");
                if (paths.targetDir != null) {
                  targetDir =
                      Directory("${destinationDir.path}/${paths.targetDir}");
                }

                //Create the target directory if it doesn't exist
                if (await targetDir.exists() == false) {
                  await targetDir.create(recursive: true);
                }

                //Move the file
                final destinationPath =
                    "${targetDir.path}/${paths.targetFileName}.$videoExtension";
                print('Moving file ${file.path} to $destinationPath');

                //Move the file to the correct directory
                await file.rename(destinationPath);

                //Delete the source directory if it is empty
                print('Deleting directory as moved file');
                await sourceDirectory.delete(recursive: true);
              }
            }

            //Delete the file if it is in the ignore list
            for (var ignoreExtension in ignoreFiles) {
              if (extension.toLowerCase() == ignoreExtension.toLowerCase()) {
                await file.delete();
              }
            }
          }
        }
      }

      //Delete the directory if it is empty after moving the file
      final bool sourceDirStillExists = await sourceDirectory.exists();
      if (sourceDirStillExists &&
          (await sourceDirectory.list().toList()).isEmpty) {
        print('deleting empty directory ${sourceDirectory.path}');
        await sourceDirectory.delete(recursive: true);
      }
    }
  }
}

/// A class that represents the result of parsing a file name
class NameParserResult {
  /// The directory that the file should be moved to
  final String? targetDir;

  /// The name that the file should be renamed to
  final String targetFileName;

  NameParserResult({this.targetDir, required this.targetFileName});
}
