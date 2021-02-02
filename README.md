# streamf-testing
A bunch of testing files for METU CENG536 Fall"20 Homework 3, a Linux kernel character device driver, basically a horrible bash script and its friends!

To use it, clone the repository into your working directory and then just run the script!

```sh
git clone https://github.com/denizmsayin/streamf-testing
cd streamf-testing
./scripted_test
```

The script will ask for your root password and only use root access to load/unload the module. I take no responsibility for freezing/crashing your system! Those would probably be caused by bugs in your module.

### How to make the script work?

Obviously the script has some expectations, since we don't exactly have uniform requirements for the homework:

* The directory into which you cloned the repository must contain the executable loading and unloading scripts `streamf_load` and `streamf_unload`
* Your devices must be named `streamf`, being accessible as `/dev/streamf0`, `/dev/streamf1`, `/dev/streamf67` (when loaded with many devices) etc.
* For filtering, the filter control user program `filter_cntl.c` contains `ioctl` macros, along with the `struct filter_struct` and `enum FilterType` definitions. These should be binary-compatible with the ones your module was compiled with. This means that the `struct` layout, `enum` values and macro values you compiled with have to be the same, even though the names etc. can change. 

The names/directories etc. can be modified with some flags present at the top of the `scripted_test` script, but I recommend not changing it so that you don't get merge conflicts when you `git pull` in case I update the script.

### Details about the tests

Although there are quite a few tests, they are pretty basic and are by no extensive at all since there are so many possible things that can be done with the filters and devices.

* For most tests, the script stops in case the test fails since there are state changes that need to be consistent between tests. Feel free to comment some tests out inside the script though, it should be pretty easy to see what is where.

* There are no real parallel tests, at most 1 reader & 1 writer work concurrently when testing with big files. Cases with multiple readers or multiple writers do not exist, most operations are sequential.
* There are no very complicated tests using 10 random filters on both ends with huge data I/O etc., most of the tests are hand-crafted and basic.
* Since we've probably understood some requirements differently, some tests may fail even though your implementation isn't buggy. Also, there might be bugs I haven't noticed in the tests as well since the device is a complicated beast. In case of such problems, write under the thread (or send me a PM) on COW, or open an issue here. Anything goes!