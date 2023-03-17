// SPDX-License-Identifier: MIT
pragma solidity >=0.8.17;

contract C9SVGFlags {
    /**
     * @dev Optimized SVG flags. Storage of these would cost around ~2.2M gas.
     */
    bytes constant FLG_BLK = ""
        "<pattern id='ptrn' width='.1' height='.1'>"
        "<rect width='64' height='48' fill='#def' stroke='#000'/>"
        "</pattern>"
        "<path d='M0 0h640v480H0z' fill='url(#ptrn)'/>";
    bytes constant FLG_CAN = ""
        "<path fill='#fff' d='M0 0h640v480H0z'/>"
        "<path fill='#d21' d='M-19.7 0h169.8v480H-19.7zm509.5 0h169.8v480H489.9zM201 232l-13.3 4.4 61.4 54c4.7 13.7-1.6 "
        "17.8-5.6 25l66.6-8.4-1.6 67 13.9-.3-3.1-66.6 66.7 8c-4.1-8.7-7.8-13.3-4-27.2l61.3-51-10.7-4c-8.8-6.8 3.8-32.6 "
        "5.6-48.9 0 0-35.7 12.3-38 5.8l-9.2-17.5-32.6 35.8c-3.5.9-5-.5-5.9-3.5l15-74.8-23.8 13.4c-2 .9-4 .1-5.2-2.2l-23-46-23.6 "
        "47.8c-1.8 1.7-3.6 1.9-5 .7L264 130.8l13.7 74.1c-1.1 3-3.7 3.8-6.7 2.2l-31.2-35.3c-4 6.5-6.8 17.1-12.2 19.5-5.4 "
        "2.3-23.5-4.5-35.6-7 4.2 14.8 17 39.6 9 47.7z'/>";
    bytes constant FLG_CHN = ""
        "<g id='c9chn'>"
        "<path fill='#ff0' d='M-.6.8 0-1 .6.8-1-.3h2z'/>"
        "</g>"
        "<path fill='#e12' d='M0 0h640v480H0z'/>"
        "<use href='#c9chn' transform='matrix(72 0 0 72 120 120)'/>"
        "<use href='#c9chn' transform='matrix(-12.3 -20.6 20.6 -12.3 240.3 48)'/>"
        "<use href='#c9chn' transform='matrix(-3.4 -23.8 23.8 -3.4 288 96)'/>"
        "<use href='#c9chn' transform='matrix(6.6 -23 23 6.6 288 168)'/>"
        "<use href='#c9chn' transform='matrix(15 -18.7 18.7 15 240 216)'/>";
    bytes constant FLG_GER = ""
        "<path fill='#fc0' d='M0 320h640v160H0z'/>"
        "<path d='M0 0h640v160H0z'/>"
        "<path fill='#d00' d='M0 160h640v160H0z'/>";
    bytes constant FLG_IND = ""
        "<path fill='#e01' d='M0 0h640v249H0z'/>"
        "<path fill='#fff' d='M0 240h640v240H0z'/>";
    bytes constant FLG_KOR = ""
        "<defs>"
        "<clipPath id='c9kor1'>"
        "<path fill-opacity='.7' d='M-95.8-.4h682.7v512H-95.8z'/>"
        "</clipPath>"
        "</defs>"
        "<g fill-rule='evenodd' clip-path='url(#c9kor1)' transform='translate(89.8 .4) scale(.94)'>"
        "<path fill='#fff' d='M-95.8-.4H587v512H-95.8Z'/>"
        "<g transform='rotate(-56.3 361.6 -101.3) scale(10.67)'>"
        "<g id='c9kor2'>"
        "<path id='c9kor3' d='M-6-26H6v2H-6Zm0 3H6v2H-6Zm0 3H6v2H-6Z'/>"
        "<use href='#c9kor3' y='44'/>"
        "</g>"
        "<path stroke='#fff' d='M0 17v10'/>"
        "<path fill='#c33' d='M0-12a12 12 0 0 1 0 24Z'/>"
        "<path fill='#04a' d='M0-12a12 12 0 0 0 0 24A6 6 0 0 0 0 0Z'/>"
        "<circle cy='-6' r='6' fill='#c33'/>"
        "</g>"
        "<g transform='rotate(-123.7 191.2 62.2) scale(10.67)'>"
        "<use href='#c9kor2'/>"
        "<path stroke='#fff' d='M0-23.5v3M0 17v3.5m0 3v3'/>"
        "</g>"
        "</g>";
    bytes constant FLG_UK  = ""
        "<path fill='#026' d='M0 0h640v480H0z'/>"
        "<path fill='#fff' d='m75 0 244 181L562 0h78v62L400 241l240 178v61h-80L320 301 81 480H0v-60l239-178L0 64V0h75z'/>"
        "<path fill='#c12' d='m424 281 216 159v40L369 281h55zm-184 20 6 35L54 480H0l240-179zM640 0v3L391 191l2-44L590 0h50zM0 0l239 176h-60L0 42V0z'/>"
        "<path fill='#fff' d='M241 0v480h160V0H241zM0 160v160h640V160H0z'/>"
        "<path fill='#c12' d='M0 193v96h640v-96H0zM273 0v480h96V0h-96z'/>";
    bytes constant FLG_US  = ""
        "<path fill='#fff' d='M0 0h640v480H0z'/>"
        "<g id='c9uss'>"
        "<path fill='#fff' d='m30.4 11 3.4 10.3h10.6l-8.6 6.3 3.3 10.3-8.7-6.4-8.6 6.3L25 27.6l-8.7-6.3h10.9z'/>"
        "</g>"
        "<g id='c9uso'>"
        "<use href='#c9uss'/>"
        "<use href='#c9uss' y='51.7'/>"
        "<use href='#c9uss' y='103.4'/>"
        "<use href='#c9uss' y='155.1'/>"
        "<use href='#c9uss' y='206.8'/>"
        "</g>"
        "<g id='c9use'>"
        "<use href='#c9uss' y='25.9'/>"
        "<use href='#c9uss' y='77.6'/>"
        "<use href='#c9uss' y='129.5'/>"
        "<use href='#c9uss' y='181.4'/>"
        "</g>"
        "<g id='c9usa'>"
        "<use href='#c9uso'/>"
        "<use href='#c9use' x='30.4'/>"
        "</g>"
        "<path fill='#b02' d='M0 0h640v37H0zm0 73.9h640v37H0zm0 73.8h640v37H0zm0 73.8h640v37H0zm0 74h640v36.8H0zm0 73.7h640v37H0zM0 443h640V480H0z'/>"
        "<path fill='#026' d='M0 0h364.8v259H0z'/>"
        "<use href='#c9usa'/>"
        "<use href='#c9usa' x='60.8'/>"
        "<use href='#c9usa' x='121.6'/>"
        "<use href='#c9usa' x='182.4'/>"
        "<use href='#c9usa' x='243.2'/>"
        "<use href='#c9uso' x='304'/>";

    function getSVGFlag(uint256 flagId)
    external pure
    returns(bytes memory flag) {
        flag = "<svg version='1.1' xmlns='http://www.w3.org/2000/svg' viewBox='0 0 640 480'>";
        if (flagId == 0) {
            flag = bytes.concat(flag, FLG_CAN);
        }
        else if (flagId == 1) {
            flag = bytes.concat(flag, FLG_CHN);
        }
        else if (flagId == 2) {
            flag = bytes.concat(flag, FLG_GER);
        }
        else if (flagId == 3) {
            flag = bytes.concat(flag, FLG_IND);
        }
        else if (flagId == 4) {
            flag = bytes.concat(flag, FLG_KOR);
        }
        else if (flagId == 5) {
            flag = bytes.concat(flag, FLG_UK);
        }
        else if (flagId == 6) {
            flag = bytes.concat(flag, FLG_US);
        }
        else {
            flag = bytes.concat(flag, FLG_BLK);
        }
        flag = bytes.concat(flag, "</svg>");
    }
}
