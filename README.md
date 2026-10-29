# Tessa installer

The first step of installing Tessa, One Thousand Pieces' internal AI teammate. These two files install git and the GitHub CLI, sign you in to GitHub, and copy the team's private repository. They only work for members of the OneThousandPieces GitHub organisation; Tessa herself is not in this repository.

**Mac** (Terminal):

```
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/OneThousandPieces/tessa-install/main/get-tessa.sh)"
```

**Windows** (PowerShell):

```
irm https://raw.githubusercontent.com/OneThousandPieces/tessa-install/main/get-tessa.ps1 | iex
```

These files are copies of `scripts/install/` in the team's repository, where they are maintained.
