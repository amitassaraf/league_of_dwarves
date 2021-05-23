#define ELEMENTS_PER_GROUP 65536 //max # of elements to be processes by a group

#define FACE_TOP = 1; // 000
#define FACE_BOTTOM = 2; // 010
#define FACE_LEFT = 4; // 100
#define FACE_RIGHT = 8; // 1000
#define FACE_FRONT = 16;  // 10000
#define FACE_BACK = 32; // 100000

#define LEFT_RIGHT_FACE_BITS_TEST = 1;  // 0b001
#define FRONT_BACK_FACE_BITS_TEST = 2; // 0b010
#define TOP_BOTTOM_FACE_BITS_TEST = 4; // 0b100

// Leading zeros of 32 bit number
inline int __clzsi2(int a) {
  uint x = (uint)a;
  int t = ((x & 0xFFFF0000) == 0) << 4;
  x >>= 16 - t;
  uint r = t;
  t = ((x & 0xFF00) == 0) << 3;
  x >>= 8 - t; 
  r += t;
  t = ((x & 0xF0) == 0) << 2;
  x >>= 4 - t; 
  r += t;      
  t = ((x & 0xC) == 0) << 1;
  x >>= 2 - t;
  r += t;
  return r + ((2 - x) & -((x & 2) == 0));
}

// leading zeros of 64 bit number
inline int __clzdi2(ulong val)
{
  if (val >> 32)
    {
      return __clzsi2(val >> 32);
    }
  else
    {
      return __clzsi2(val) + 32;
    }
}

inline ulong calculateSibling(ulong startLocation, uchar mask, uchar whileThis, bool backwardIsOr) {
        ulong target = startLocation;
        ulong path = 0;
        uchar count = 0;
        uchar latest = 0;
        while ((target & mask) == whileThis && target > 1) {
            latest = target & 7;
            if (backwardIsOr) {
                path = path | ((latest | mask) << (3 * count));
            } else {
                path = path | ((latest ^ mask) << (3 * count));
            }
            target = target >> 3;
            count += 1;
        }
        if (target == 1) {
            return 1;
        } 
        
        if (backwardIsOr) {
            target = target ^ mask;
        } else {
            target = target | mask;
        }
        target = target << (3 * count);
        target = target | path;
        return target;
    }

inline int findLocationalCodeIndex(__global ulong* octreeCodes, int totalNodes, ulong locationalCode) 
{ 
    int l = 0;
    while (l <= totalNodes) { 
        int m = l + (totalNodes - l) / 2; 
        if (octreeCodes[m] == locationalCode) 
            return m; 
        if (octreeCodes[m] < locationalCode) 
            l = m + 1;
        else
            totalNodes = m - 1; 
    }  
    return -1;
} 

inline bool isLeaf(__global ulong* octreeCodes, int totalNodes, ulong locationalCode) {
    return findLocationalCodeIndex(octreeCodes, totalNodes, locationalCode << 3) != -1;
}

inline bool isSolid(__global uchar* octreeSolids, ulong locationalCodeIndex) {
    return octreeSolids[locationalCodeIndex] == 1;
}

inline bool isDirection(uchar localCode, uchar direction) {
    if (direction == FACE_TOP) {
        return (localCode & 4) == 0;
    } else if (direction == FACE_BOTTOM) {
        return (localCode & 4) == 4;
    } else if (direction == FACE_FRONT) {
        return (localCode & 2) == 2;
    } else if (direction == FACE_BACK) {
        return (localCode & 2) == 0;
    } else if (direction == FACE_LEFT) {
        return (localCode & 1) == 1;
    } else if (direction == FACE_RIGHT) {
        return (localCode & 1) == 0;
    }
    return false;
}

inline uchar getDepth(ulong locationalCode) {
    return (63-__clzdi2(locationalCode))/3;
}

inline int getSize(int octreeSize, ulong locationalCode) {
    return octreeSize / pow((float)2, (float)getDepth(locationalCode));
}

inline bool visitAll(__global ulong* octreeCodes, __global uchar* octreeSolids, int octreeSize, int totalNodes, 
              ulong locationalCode, uchar direction, ushort nodeSize, ulong sibling, 
              ulong faceBitsTestMask, bool expectingZeroResult) {
    if (!isDirection(locationalCode, direction) || getSize(octreeSize, locationalCode) > nodeSize)
        return true;
    
    if (!isLeaf(octreeCodes, totalNodes, locationalCode)) {
        for (int i=0; i<8; i++) {
            ulong locCodeChild = (locationalCode<<3)|i;
            if (!visitAll(octreeCodes, octreeSolids, octreeSize, totalNodes, locationalCode, direction, nodeSize, locCodeChild, faceBitsTestMask, expectingZeroResult)) {
                return false;
            }
        }
        return true;
    }
                    
    uchar depth = getDepth(locationalCode) - getDepth(sibling);
    ulong hyperLocalCode = ((locationalCode >> (3 * depth)) << (3 * depth)) ^ locationalCode;
    ulong hyperFaceBitsTestMask = faceBitsTestMask;
    for (uchar i = 0; i < depth - 1; i++) {
        hyperFaceBitsTestMask = (hyperFaceBitsTestMask << 3) | faceBitsTestMask;
    }
    
    bool solidFlag = true;
    if (expectingZeroResult) {
        if ((hyperLocalCode & hyperFaceBitsTestMask) == hyperFaceBitsTestMask) {
            if (!isSolid(octreeSolids, findLocationalCodeIndex(octreeCodes, totalNodes, locationalCode))) {
                solidFlag = false;
            }
        }
    } else {
        if ((hyperLocalCode & hyperFaceBitsTestMask) == 0) {
            if (!isSolid(octreeSolids, findLocationalCodeIndex(octreeCodes, totalNodes, locationalCode))) {
                solidFlag = false;
            }
        }
    }

    return solidFlag;
}


inline bool checkIfSiblingIsSolid(__global ulong* octreeCodes, __global uchar* octreeSolids, int octreeSize, int totalNodes, 
                           ulong siblingLocationalCode, ushort nodeSize,
                           ulong faceBitsTestMask, bool expectingZeroResult, uchar direction) {
    while (siblingLocationalCode > 1) {
        int siblingLocationalCodeIndex = findLocationalCodeIndex(octreeCodes, totalNodes, siblingLocationalCode);
        if (siblingLocationalCodeIndex != -1) {
            ulong sibling = siblingLocationalCode;
            if (!isLeaf(octreeCodes, totalNodes, sibling)) {
                // Find its smaller children that might hiding our face
                bool solidFlag = visitAll(octreeCodes, octreeSolids, octreeSize, totalNodes, siblingLocationalCode, direction, nodeSize, sibling, faceBitsTestMask, expectingZeroResult);
                if (!solidFlag) {
                    return false;
                }
            } else if (!isSolid(octreeSolids, siblingLocationalCodeIndex)) {
                return false;
            }

            return true;
        }
        siblingLocationalCode = siblingLocationalCode >> 3;
    }

    // Couldn't find surface
    return true;
}

__kernel void cullFaces(__global ulong* octreeCodes, __global uchar* octreeSolids, int octreeSize, int totalNodes, __global uchar* masks) {
    int wgId = get_group_id(0);
    int wgSize = get_local_size(0);
    int itemId = get_local_id(0);

    int startIndex = wgId * ELEMENTS_PER_GROUP;
    int endIndex = startIndex + ELEMENTS_PER_GROUP;
    if(endIndex > n){
        endIndex = n;
    }

    for(int locationalCodeIndex=startIndex + itemId; locationalCodeIndex<endIndex; locationalCodeIndex+= wgSize){
        ulong locationalCode = octreeCodes[locationalCodeIndex];
        
        uchar faceMask = 0;
        if (isLeaf(octreeCodes, totalNodes, locationalCodeIndex)) {
            masks[locationalCodeIndex] = faceMask;
            return;
        }

        if (!isSolid(octreeSolids, locationalCodeIndex)) {
            masks[locationalCodeIndex] = faceMask;
            return;
        }
        
        printf("Here!");

        ushort nodeSize = getSize(octreeSize, locationalCode);

        ulong left = 0;
        ulong right = 0;
        ulong back = 0;
        ulong front = 0;
        ulong north = 0;
        ulong south = 0;
        if ((locationalCode & 4) == 4) { // Are we a top node
            north = calculateSibling(locationalCode, 4, 4, false);
            
            south = locationalCode ^ 4;
        } else { // We are a bottom node
            south = calculateSibling(locationalCode, 4, 0, true);
            
            north = locationalCode | 4;
        }
        // Get left and right
        if ((locationalCode & 1) == 1) { // Are we a right node?
            right = calculateSibling(locationalCode, 1, 1, false);

            left = locationalCode ^ 1;
        } else { // We are a right node
            left = calculateSibling(locationalCode, 1, 0, true);

            right = locationalCode | 1;
        }

        // Get back and front
        if ((locationalCode & 2) == 2) { // Are we a back node?
            back = calculateSibling(locationalCode, 2, 2, false);

            front = locationalCode ^ 2;
        } else { // We are a front node
            front = calculateSibling(locationalCode, 2, 0, true);

            back = locationalCode | 2;
        }

        if (!checkIfSiblingIsSolid(octreeCodes, octreeSolids, octreeSize, totalNodes, north, nodeSize, TOP_BOTTOM_FACE_BITS_TEST, false, FACE_TOP)) {
            faceMask |= FACE_TOP;
        }

        if (!checkIfSiblingIsSolid(octreeCodes, octreeSolids, octreeSize, totalNodes, south, nodeSize, TOP_BOTTOM_FACE_BITS_TEST, true, FACE_BOTTOM)) {
            faceMask |= FACE_BOTTOM;
        }

        if (!checkIfSiblingIsSolid(octreeCodes, octreeSolids, octreeSize, totalNodes, front, nodeSize, FRONT_BACK_FACE_BITS_TEST, true, FACE_FRONT)) {
            faceMask |= FACE_FRONT;
        }

        if (!checkIfSiblingIsSolid(octreeCodes, octreeSolids, octreeSize, totalNodes, back, nodeSize, FRONT_BACK_FACE_BITS_TEST, false, FACE_BACK)) {
            faceMask |= FACE_BACK;
        }

        if (!checkIfSiblingIsSolid(octreeCodes, octreeSolids, octreeSize, totalNodes, left, nodeSize, LEFT_RIGHT_FACE_BITS_TEST, true, FACE_LEFT)) {
            faceMask |= FACE_LEFT;
        }

        if (!checkIfSiblingIsSolid(octreeCodes, octreeSolids, octreeSize, totalNodes, right, nodeSize, LEFT_RIGHT_FACE_BITS_TEST, false, FACE_RIGHT)) {
            faceMask |= FACE_RIGHT;
        }

        printf("Setting mask!");
        masks[locationalCodeIndex] = faceMask;          
    }
}