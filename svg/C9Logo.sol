// SPDX-License-Identifier: MIT
pragma solidity >=0.8.17;

contract C9SVGLogo {
    bytes constant LOGO = ""
    "<svg version='1.1' xmlns='http://www.w3.org/2000/svg' width='100%' height='100%' viewBox='0 0 256 276'>"
    "<defs>"
        "<radialGradient id='c9r1' cx='40%' cy='80%' r='50%'>"
            "<stop offset='.2' stop-color='#2fd'/>"
            "<stop offset='1' stop-color='#0a6'/>"
        "</radialGradient>"
        "<radialGradient id='c9r2' cx='50%' cy='80%' r='50%'>"
            "<stop offset='.2' stop-color='#09f'/>"
            "<stop offset='1' stop-color='#03a'/>"
        "</radialGradient>"
        "<radialGradient id='c9r3' cx='50%' cy='80%' r='50%'>"
            "<stop offset='.2' stop-color='#2ff'/>"
            "<stop offset='1' stop-color='#0a9'/>"
        "</radialGradient>"
    "</defs>"
    "<symbol id='c9p'>"
        "<path d='M122.4,2,26,57.5a11,11,0,0,0,0,19.4h0a11,11,0,0,0,11,0l84-48.5V67L74.3,94.3a6,6,0,0,0,0,10L125,134a6,6,0,0,0,6,0l98.7-57a11,11,0,0,0,0-19.4L133.6,2A11,11,0,0,0,122.4,2Zm12,65V28.5l76,44-33.5,19.3Z'/>"
    "</symbol>"
    "<use href='#c9p' fill='url(#c9r2)'/>"
    "<use href='#c9p' transform='translate(0 9.3) rotate(240 125 138)' fill='url(#c9r3)'/>"
    "<use href='#c9p' transform='translate(9 4) rotate(120 125 138)' fill='url(#c9r1)'/>"
    "</svg>";

    function getSVGLogo()
    external pure
    returns (bytes memory) {
        return LOGO;
    }
}