### How to set up the morack-bin

Simply clone this repository to your ``$HOME`` directory on **JUSTUS 2** by running the command:
```
git clone https://github.com/paul-meiners/morack-bin.git
```
Add the following to the end of your ``$HOME/.bashrc`` file to set up with the included ``setPATH.sh`` script:
```
source $HOME/morack-bin/setPATH.sh
```
You will need to reload ``.bashrc`` by starting a new session for the changes to take effect.<br/><br/>


Alternatively, you can just copy individual scripts to your ``$HOME/bin`` directory or similar, e.g. like this:
```
wget https://raw.githubusercontent.com/paul-meiners/morack-bin/refs/heads/main/suborca.sh
```
The above example downloads the raw contents of ``suborca.sh`` to your current working directory.

Make the script executable with ``chmod +x`` and ensure its directory is on your ``$PATH`` for easy execution.<br/><br/>



### Included scripts and what they do

     ``smiles2xyz.sh``      Creates an optimized .xyz file from a SMILES string using **OpenBabel** and **xTB**.

     ``suborca.sh``            Automates the submission of **ORCA** calculations to the **SLURM** scheduler.

     ``thermorca.sh``        Takes an **ORCA** output file and reads out thermodynamic information.
