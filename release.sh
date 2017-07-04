#!/bin/sh

# By Umesh Ghimire, based on work by Mike Jolley;)
# License: GPL v3

# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.

# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.

# You should have received a copy of the GNU General Public License
# along with this program.  If not, see <http://www.gnu.org/licenses/>

# ----- START EDITING HERE -----

# THE GITHUB ACCESS TOKEN, GENERATE ONE AT: https://github.com/settings/tokens

DIRECTORY_SEPERATOR="\\";
RELEASE_DIRECTORY="D:\\plugin_released\\" # change release directory

if [ -z "$1" ]
  then
    echo "No argument supplied"
    exit 1;
fi

PLUGIN_SLUG="$1"

PLUGIN_PATH=${RELEASE_DIRECTORY}${PLUGIN_SLUG}"-git"${DIRECTORY_SEPERATOR}
PLUGIN_INI_PATH="$RELEASE_DIRECTORY$PLUGIN_SLUG.ini"

if [ ! -e "$PLUGIN_INI_PATH" ]
then
    echo "Configuration file not exists."
    exit 1;
fi

while IFS='= ' read var val
do
    if [[ $var == \[*] ]]
    then
        section=$var
    elif [[ $val ]]
    then
        declare "$var$section=$val"
    fi

done < "$PLUGIN_INI_PATH"

if [  -z "$GITHUB_ACCESS_TOKEN" ]
   then
    echo "GITHUB_ACCESS_TOKEN not set $PLUGIN_INI_PATH.";
    exit 1;
fi
if [  -z "$GITHUB_REPO_OWNER" ]
   then
    echo "GITHUB_REPO_OWNER not set $PLUGIN_INI_PATH.";
    exit 1;
fi
if [  -z "$GITHUB_REPO_NAME" ]
   then
    echo "GITHUB_REPO_NAME not set $PLUGIN_INI_PATH.";
    exit 1;
fi
if [  -z "$PLUGIN_SLUG" ]
   then
    echo "PLUGIN_SLUG not set $PLUGIN_INI_PATH.";
    exit 1;
fi
if [  -z "$IGNORE_FILES" ]
   then
    echo "IGNORE_FILES not set $PLUGIN_INI_PATH.";
    exit 1;
fi

GITHUB_REPO_OWNER="$(echo -e "${GITHUB_REPO_OWNER}" | tr -d '[:space:]')"
PLUGIN_SLUG="$(echo -e "${PLUGIN_SLUG}" | tr -d '[:space:]')"
GITHUB_REPO_NAME="$(echo -e "${GITHUB_REPO_NAME}" | tr -d '[:space:]')"
GITHUB_ACCESS_TOKEN="$(echo -e "${GITHUB_ACCESS_TOKEN}" | tr -d '[:space:]')"

# ----- STOP EDITING HERE -----

set -e
clear

# ASK INFO
echo "--------------------------------------------"
echo "      Github to WordPress.org RELEASER      "
echo "--------------------------------------------"
read -p "TAG AND RELEASE VERSION: " VERSION
echo "--------------------------------------------"
echo ""
echo "Before continuing, confirm that you have done the following :)"
echo ""
read -p " - Added a changelog for "${VERSION}"?"
read -p " - Set version in the readme.txt and main file to "${VERSION}"?"
read -p " - Set stable tag in the readme.txt file to "${VERSION}"?"
read -p " - Updated the POT file?"
read -p " - Committed all changes up to GITHUB?"
echo ""
read -p "PRESS [ENTER] TO BEGIN RELEASING "${VERSION}


# VARS
ROOT_PATH=$(pwd)"/"
TEMP_GITHUB_REPO=$PLUGIN_PATH
TEMP_SVN_REPO=${PLUGIN_PATH}"-svn"
SVN_REPO="http://plugins.svn.wordpress.org/"${PLUGIN_SLUG}"/"
GIT_REPO="git@github.com:"${GITHUB_REPO_OWNER}"/"${GITHUB_REPO_NAME}".git"

# DELETE OLD TEMP DIRS
rm -Rf $TEMP_GITHUB_REPO
rm -Rf $TEMP_SVN_REPO
# CHECKOUT SVN DIR IF NOT EXISTS
if [[ ! -d $TEMP_SVN_REPO ]];
then
	echo "Checking out WordPress.org plugin repository"
	svn checkout $SVN_REPO $TEMP_SVN_REPO || { echo "Unable to checkout repo."; exit 1; }
fi

 # CLONE GIT DIR
 echo "Cloning GIT repository from GITHUB"
git clone --progress $GIT_REPO $TEMP_GITHUB_REPO || { echo "Unable to clone repo."; exit 1; }

# MOVE INTO GIT DIR
cd $PLUGIN_PATH

# LIST BRANCHES
clear
git fetch origin
echo "WHICH BRANCH DO YOU WISH TO DEPLOY?"
git branch -r || { echo "Unable to list branches."; exit 1; }
echo ""
read -p "origin/" BRANCH

# Switch Branch
echo "Switching to branch"
git checkout ${BRANCH} || { echo "Unable to checkout branch."; exit 1; }

echo ""
read -p "PRESS [ENTER] TO DEPLOY BRANCH "${BRANCH}

# REMOVE UNWANTED FILES & FOLDERS
echo "Removing unwanted files files are :$IGNORE_FILES"
export IFS=","
 for word in $IGNORE_FILES; do
        PASSED_PATH_BEFORE_TRIM="$PLUGIN_PATH""${word////$DIRECTORY_SEPERATOR}"
         PASSED_PATH="${PASSED_PATH_BEFORE_TRIM##*( )}"
        if [[ -d $PASSED_PATH ]]; then


            rm -Rf "$PASSED_PATH"
            echo "$PASSED_PATH is a directory deleted."

        elif [[ -f $PASSED_PATH ]]; then

             rm -f "$PASSED_PATH"
             echo "$PASSED_PATH is a file deleted."
        fi

done
echo "Finally done"
exit 1;

# MOVE INTO SVN DIR
cd $TEMP_SVN_REPO

# UPDATE SVN
echo "Updating SVN"
svn update || { echo "Unable to update SVN."; exit 1; }

# DELETE TRUNK
echo "Replacing trunk"
rm -Rf trunk/

# COPY GIT DIR TO TRUNK
cp -R $TEMP_GITHUB_REPO trunk/

# DO THE ADD ALL NOT KNOWN FILES UNIX COMMAND
svn add --force * --auto-props --parents --depth infinity -q

# DO THE REMOVE ALL DELETED FILES UNIX COMMAND
MISSING_PATHS=$( svn status | sed -e '/^!/!d' -e 's/^!//' )

# iterate over filepaths
for MISSING_PATH in $MISSING_PATHS; do
    svn rm --force "$MISSING_PATH"
done

# COPY TRUNK TO TAGS/$VERSION
echo "Copying trunk to new tag"
svn copy trunk tags/${VERSION} || { echo "Unable to create tag."; exit 1; }

# DO SVN COMMIT
clear
echo "Showing SVN status"
svn status

# PROMPT USER
echo ""
read -p "PRESS [ENTER] TO COMMIT RELEASE "${VERSION}" TO WORDPRESS.ORG AND GITHUB"
echo ""

# CREATE THE GITHUB RELEASE
echo "Creating GITHUB release"
API_JSON=$(printf '{ "tag_name": "%s","target_commitish": "%s","name": "%s", "body": "Release of version %s", "draft": false, "prerelease": false }' $VERSION $BRANCH $VERSION $VERSION)
RESULT=$(curl --data "${API_JSON}" https://api.github.com/repos/${GITHUB_REPO_OWNER}/${GITHUB_REPO_NAME}/releases?access_token=${GITHUB_ACCESS_TOKEN})

# DEPLOY
echo ""
echo "Committing to WordPress.org...this may take a while..."
svn commit -m "Release "${VERSION}", see readme.txt for the changelog." || { echo "Unable to commit."; exit 1; }

# REMOVE THE TEMP DIRS
echo "CLEANING UP"
rm -Rf $TEMP_GITHUB_REPO
rm -Rf $TEMP_SVN_REPO

# DONE, BYE
echo "RELEASER DONE :D"
