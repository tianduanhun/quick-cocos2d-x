#ifndef Cocos2Dx_HelperFunc_h
#define Cocos2Dx_HelperFunc_h
#include "cocos2d.h"
NS_CC_BEGIN
class CZHelperFunc
{
public:
    static unsigned char* getFileData(const char* pszFileName, const char* pszMode, unsigned long * pSize);
};
NS_CC_END
#endif //Cocos2Dx_HelperFunc_h
