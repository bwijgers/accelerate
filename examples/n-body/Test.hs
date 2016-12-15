
module Test (makeTests)
  where

import Common.Type

import Prelude                                          as P
import Data.Array.Accelerate                            as A
import Data.Array.Accelerate.Examples.Internal

-- Generate the tests
--
makeTests :: (Scalar Time -> Vector Body -> Vector Body) -> [Test]
makeTests step =
  [ testCase "t=0"  $ assertEqual t0  t0'
  , testCase "t=10" $ assertEqual t10 t10'
  , testCase "t=20" $ assertEqual t20 t20'
  , testCase "t=30" $ assertEqual t30 t30'
  , testCase "t=40" $ assertEqual t40 t40'
  , testCase "t=50" $ assertEqual t50 t50'
  ]
  where
    advance     = foldl1 (.) (P.replicate 10 (step dt))
    t0'         = step (fromList Z [0]) bodies
    t10'        = advance t0'
    t20'        = advance t10'
    t30'        = advance t20'
    t40'        = advance t30'
    t50'        = advance t40'


-- Input data
--
bodies :: Vector Body
bodies = fromList (Z :. 32) [((V3 49.934765 48.864784 49.504097,3.456227),V3 10.561408 (-10.792668) 10.699586,V3 0.0 0.0 0.0),((V3 (-19.72055) 21.0447 21.976465,63.459526),V3 6.989762 6.5499606 7.2992377,V3 0.0 0.0 0.0),((V3 (-8.485103) 70.43111 (-66.07767),74.34554),V3 14.306272 1.7235309 (-13.421982),V3 0.0 0.0 0.0),((V3 (-40.529545) (-23.411388) (-23.874193),8.434827),V3 (-6.4595428) 11.182692 (-6.5872374),V3 0.0 0.0 0.0),((V3 36.915504 (-13.378705) 22.885813,16.776989),V3 (-3.9690585) (-10.951718) 6.7895308,V3 0.0 0.0 0.0),((V3 58.12199 47.11681 49.27831,21.63172),V3 9.955754 (-12.281143) 10.4124775,V3 0.0 0.0 0.0),((V3 (-18.56515) 19.121122 19.856537,69.831604),V3 6.6335444 6.440665 6.8886757,V3 0.0 0.0 0.0),((V3 (-16.319696) 68.65275 (-70.91549),66.98223),V3 13.727621 3.263243 (-14.180073),V3 0.0 0.0 0.0),((V3 (-35.320797) (-9.581309) (-15.5530615),23.477612),V3 (-3.0388143) 11.202367 (-4.932819),V3 0.0 0.0 0.0),((V3 35.467846 (-31.458008) 57.63878,4.5274367),V3 (-7.2828484) (-8.211167) 13.343963,V3 0.0 0.0 0.0),((V3 22.741138 16.762173 47.443493,45.534313),V3 4.5114946 (-6.1207175) 12.769291,V3 0.0 0.0 0.0),((V3 (-19.066488) 32.53443 19.284454,37.293446),V3 9.998227 5.859364 5.926348,V3 0.0 0.0 0.0),((V3 (-4.6187997) 54.83043 (-69.1615),52.771004),V3 11.664729 0.9826122 (-14.713549),V3 0.0 0.0 0.0),((V3 (-37.741123) (-23.498236) (-29.302645),83.92678),V3 (-6.4404936) 10.344243 (-8.03139),V3 0.0 0.0 0.0),((V3 36.013374 (-17.063395) 32.41684,13.032608),V3 (-4.7614217) (-10.049282) 9.045693,V3 0.0 0.0 0.0),((V3 49.562435 83.03267 83.920395,18.12446),V3 14.676114 (-8.760214) 14.83302,V3 0.0 0.0 0.0),((V3 (-9.462863) 25.536043 36.41799,53.132633),V3 7.573575 2.8065314 10.800983,V3 0.0 0.0 0.0),((V3 (-10.790539) 66.63314 (-67.998985),94.62536),V3 13.614646 2.204749 (-13.893719),V3 0.0 0.0 0.0),((V3 (-40.558056) (-29.971233) (-24.474981),6.5728045),V3 (-8.00616) 10.834197 (-6.5379558),V3 0.0 0.0 0.0),((V3 29.8883 (-20.165321) 45.04451,53.180336),V3 (-5.309554) (-7.869626) 11.860275,V3 0.0 0.0 0.0),((V3 32.482105 30.910307 49.05143,91.3407),V3 7.583363 (-7.9689794) 12.034005,V3 0.0 0.0 0.0),((V3 (-20.018032) 19.918154 27.472118,87.52959),V3 6.346644 6.378469 8.753611,V3 0.0 0.0 0.0),((V3 (-12.006343) 50.781525 (-48.374542),75.542244),V3 12.0401945 2.8466792 (-11.469504),V3 0.0 0.0 0.0),((V3 (-36.06932) (-13.634953) (-28.24347),35.689384),V3 (-3.9444003) 10.434348 (-8.17044),V3 0.0 0.0 0.0),((V3 36.564384 (-22.889074) 41.142605,77.35545),V3 (-5.9291406) (-9.471566) 10.6575,V3 0.0 0.0 0.0),((V3 72.98635 36.489113 44.127728,34.4798),V3 7.5769863 (-15.15566) 9.163149,V3 0.0 0.0 0.0),((V3 (-6.637457) 11.754714 14.4537,20.805649),V3 5.286392 2.9850323 6.5001945,V3 0.0 0.0 0.0),((V3 (-5.4672456) 71.23518 (-59.5781),58.3743),V3 14.7713995 1.1336936 (-12.354176),V3 0.0 0.0 0.0),((V3 (-43.633926) (-22.012821) (-7.0467205),20.659788),V3 (-6.265288) 12.4190855 (-2.0056372),V3 0.0 0.0 0.0),((V3 54.48485 (-44.066643) 29.847332,82.26547),V3 (-10.098527) (-12.486015) 6.8399606,V3 0.0 0.0 0.0),((V3 50.216465 50.00622 49.413647,86.262726),V3 10.759963 (-10.805201) 10.632457,V3 0.0 0.0 0.0),((V3 (-24.18221) 1.1176014 18.39111,52.37195),V3 0.40538555 8.771569 6.670974,V3 0.0 0.0 0.0)]

dt :: Scalar Time
dt = fromList Z [0.1]

-- Take a number of steps in 0.1 second increments
--
t0, t10, t20, t30, t40, t50 :: Vector Body
t0  = fromList (Z :. 32) [((V3 49.934765 48.864784 49.504097,3.456227),V3 10.561408 (-10.792668) 10.699586,V3 (-0.2020692) (-0.18428235) (-0.13120669)),((V3 (-19.72055) 21.0447 21.976465,63.459526),V3 6.989762 6.5499606 7.2992377,V3 3.0261776 (-0.7999116) (-1.3126944)),((V3 (-8.485103) 70.43111 (-66.07767),74.34554),V3 14.306272 1.7235309 (-13.421982),V3 (-0.1371406) (-3.710925) 3.796874),((V3 (-40.529545) (-23.411388) (-23.874193),8.434827),V3 (-6.4595428) 11.182692 (-6.5872374),V3 0.42419815 0.5393226 0.31401542),((V3 36.915504 (-13.378705) 22.885813,16.776989),V3 (-3.9690585) (-10.951718) 6.7895308,V3 (-0.9118709) 0.8006712 0.2444),((V3 58.12199 47.11681 49.27831,21.63172),V3 9.955754 (-12.281143) 10.4124775,V3 (-1.5379857) (-0.9758822) (-0.7344652)),((V3 (-18.56515) 19.121122 19.856537,69.831604),V3 6.6335444 6.440665 6.8886757,V3 2.988307 (-0.41186926) (-0.9475892)),((V3 (-16.319696) 68.65275 (-70.91549),66.98223),V3 13.727621 3.263243 (-14.180073),V3 1.625271 (-2.7936146) 4.267117),((V3 (-35.320797) (-9.581309) (-15.5530615),23.477612),V3 (-3.0388143) 11.202367 (-4.932819),V3 1.208595 1.1207385 0.7841558),((V3 35.467846 (-31.458008) 57.63878,4.5274367),V3 (-7.2828484) (-8.211167) 13.343963,V3 (-0.12642522) 0.3105037 (-0.2921983)),((V3 22.741138 16.762173 47.443493,45.534313),V3 4.5114946 (-6.1207175) 12.769291,V3 (-1.232773) 2.6571987e-2 (-2.692973)),((V3 (-19.066488) 32.53443 19.284454,37.293446),V3 9.998227 5.859364 5.926348,V3 1.6313204 (-1.8151838) (-0.52129644)),((V3 (-4.6187997) 54.83043 (-69.1615),52.771004),V3 11.664729 0.9826122 (-14.713549),V3 (-0.81280035) (-0.112044565) 3.5451076),((V3 (-37.741123) (-23.498236) (-29.302645),83.92678),V3 (-6.4404936) 10.344243 (-8.03139),V3 3.5243607 5.315734 3.9011729),((V3 36.013374 (-17.063395) 32.41684,13.032608),V3 (-4.7614217) (-10.049282) 9.045693,V3 (-0.61353976) 0.70832497 (-0.11806177)),((V3 49.562435 83.03267 83.920395,18.12446),V3 14.676114 (-8.760214) 14.83302,V3 (-0.4695076) (-1.0319139) (-1.0167954)),((V3 (-9.462863) 25.536043 36.41799,53.132633),V3 7.573575 2.8065314 10.800983,V3 1.3853245 (-1.4187478) (-3.0760522)),((V3 (-10.790539) 66.63314 (-67.998985),94.62536),V3 13.614646 2.204749 (-13.893719),V3 0.56374645 (-3.55292) 5.51218),((V3 (-40.558056) (-29.971233) (-24.474981),6.5728045),V3 (-8.00616) 10.834197 (-6.5379558),V3 0.30523086 0.47446692 0.23335022),((V3 29.8883 (-20.165321) 45.04451,53.180336),V3 (-5.309554) (-7.869626) 11.860275,V3 (-1.4631323) 3.3048942 (-2.3880641)),((V3 32.482105 30.910307 49.05143,91.3407),V3 7.583363 (-7.9689794) 12.034005,V3 (-3.6304643) (-2.5821278) (-4.8232713)),((V3 (-20.018032) 19.918154 27.472118,87.52959),V3 6.346644 6.378469 8.753611,V3 4.4817963 (-0.7540304) (-3.3089616)),((V3 (-12.006343) 50.781525 (-48.374542),75.542244),V3 12.0401945 2.8466792 (-11.469504),V3 0.74818593 (-0.64892244) 1.946604),((V3 (-36.06932) (-13.634953) (-28.24347),35.689384),V3 (-3.9444003) 10.434348 (-8.17044),V3 1.5595063 1.77316 1.7561425),((V3 36.564384 (-22.889074) 41.142605,77.35545),V3 (-5.9291406) (-9.471566) 10.6575,V3 (-3.1575167) 4.8282127 (-2.4603796)),((V3 72.98635 36.489113 44.127728,34.4798),V3 7.5769863 (-15.15566) 9.163149,V3 (-3.1058714) (-0.73178864) (-0.6773815)),((V3 (-6.637457) 11.754714 14.4537,20.805649),V3 5.286392 2.9850323 6.5001945,V3 6.1454386e-2 0.3914103 0.19268043),((V3 (-5.4672456) 71.23518 (-59.5781),58.3743),V3 14.7713995 1.1336936 (-12.354176),V3 (-0.6793159) (-3.241285) 1.9731628),((V3 (-43.633926) (-22.012821) (-7.0467205),20.659788),V3 (-6.265288) 12.4190855 (-2.0056372),V3 1.3458371 1.3664191 0.22117926),((V3 54.48485 (-44.066643) 29.847332,82.26547),V3 (-10.098527) (-12.486015) 6.8399606,V3 (-4.644851) 6.0297318 (-0.19813985)),((V3 50.216465 50.00622 49.413647,86.262726),V3 10.759963 (-10.805201) 10.632457,V3 (-5.0198126) (-4.7489667) (-3.2173421)),((V3 (-24.18221) 1.1176014 18.39111,52.37195),V3 0.40538555 8.771569 6.670974,V3 2.865766 2.5242555 (-0.771268))]
t10 = fromList (Z :. 32) [((V3 60.402256 37.99447 60.14521,3.456227),V3 10.347675 (-10.957504) 10.569622,V3 (-0.22668193) (-0.14637746) (-0.13127826)),((V3 (-11.430504) 27.125307 28.753597,63.459526),V3 9.780841 5.350463 6.240201,V3 2.5433345 (-1.5698189) (-0.8167556)),((V3 5.672099 70.57071 (-77.842896),74.34554),V3 13.856287 (-1.666952) (-9.809946),V3 (-0.7218549) (-3.07428) 3.454369),((V3 (-46.79211) (-12.007825) (-30.323624),8.434827),V3 (-6.012946) 11.642888 (-6.2869954),V3 0.46778414 0.38886592 0.2849534),((V3 32.574455 (-23.946268) 29.79417,16.776989),V3 (-4.7382054) (-10.062807) 7.0655513,V3 (-0.6296934) 0.97357625 0.30322555),((V3 67.3728 34.43472 59.36437,21.63172),V3 8.367946 (-13.115515) 9.689009,V3 (-1.6421701) (-0.6976927) (-0.72507)),((V3 (-10.644274) 25.257013 26.39887,69.831604),V3 9.401735 5.590103 6.2358103,V3 2.5346236 (-1.2643027) (-0.3754633)),((V3 (-1.9366095) 70.68937 (-83.21151),66.98223),V3 15.068537 0.5764816 (-10.042387),V3 1.0556761 (-2.6000845) 4.0255356),((V3 (-37.81175) 2.0563722 (-20.14278),23.477612),V3 (-1.817153) 12.071388 (-4.190213),V3 1.2293873 0.63759214 0.687956),((V3 28.138607 (-39.52876) 70.849945,4.5274367),V3 (-7.370752) (-7.898251) 13.046776,V3 (-5.1867843e-2) 0.31481925 (-0.30228883)),((V3 26.732052 10.697684 58.990242,45.534313),V3 3.4046803 (-5.9327974) 10.0338125,V3 (-0.98696345) 0.33534586 (-2.785121)),((V3 (-8.415286) 37.529408 25.032337,37.293446),V3 11.330664 3.876094 5.60827,V3 1.0490761 (-2.1232) (-0.13574754)),((V3 6.675616 55.826862 (-82.31381),52.771004),V3 10.847925 1.0917499 (-11.286869),V3 (-0.7843886) 0.27396658 3.3349295),((V3 (-42.53744) (-10.963094) (-35.619644),83.92678),V3 (-2.7064044) 14.917309 (-4.294997),V3 3.9198356 3.8610702 3.5435603),((V3 31.007177 (-26.778881) 41.412075,13.032608),V3 (-5.2589273) (-9.285036) 8.936092,V3 (-0.38566536) 0.8186842 (-0.10571819)),((V3 64.01576 73.82858 98.300285,18.12446),V3 14.1636095 (-9.714817) 13.833233,V3 (-0.55458456) (-0.8758056) (-0.98143333)),((V3 (-1.29756) 27.675724 45.853508,53.132633),V3 8.84061 1.2858781 7.796603,V3 1.1496811 (-1.6105593) (-2.9288754)),((V3 2.984476 67.32786 (-79.47979),94.62536),V3 13.839526 (-1.0205598) (-8.638148),V3 (-8.429852e-2) (-2.9109285) 4.988788),((V3 (-48.420025) (-18.939562) (-30.91017),6.5728045),V3 (-7.6758323) 11.250289 (-6.3134418),V3 0.35382912 0.36280265 0.21467017),((V3 24.05571 (-26.526985) 55.817623,53.180336),V3 (-6.2717843) (-4.4937367) 9.426997,V3 (-0.48020265) 3.4272532 (-2.4739354)),((V3 38.412075 21.907555 58.91943,91.3407),V3 3.8768096 (-10.066701) 7.232523,V3 (-3.7875612) (-1.6009333) (-4.7642846)),((V3 (-11.713844) 25.808075 34.806118,87.52959),V3 10.581014 5.0761976 5.7207565,V3 3.913912 (-1.8188158) (-2.7121327)),((V3 0.29591668 53.392735 (-59.070557),75.542244),V3 12.523133 2.3962336 (-9.897869),V3 0.258676 (-0.2904919) 1.2244126),((V3 (-39.304882) (-2.4880366) (-35.646812),35.689384),V3 (-2.3586354) 11.898649 (-6.5040054),V3 1.6116967 1.186789 1.5703841),((V3 29.410185 (-30.127684) 50.689945,77.35545),V3 (-8.353604) (-4.429852) 8.189255,V3 (-1.6932052) 5.2191257 (-2.4670205)),((V3 79.16618 21.078148 52.9975,34.4798),V3 4.4726243 (-15.612979) 8.523445,V3 (-3.1038995) (-0.19130452) (-0.6173794)),((V3 (-1.3194776) 14.902553 21.06105,20.805649),V3 5.366333 3.3273313 6.76692,V3 0.10942383 0.29500887 0.33297652),((V3 8.919601 70.99377 (-71.09529),58.3743),V3 13.811482 (-1.798587) (-10.556653),V3 (-1.1980586) (-2.6337848) 1.6664244),((V3 (-49.27589) (-9.043354) (-8.953376),20.659788),V3 (-4.8574266) 13.547301 (-1.7893666),V3 1.4573994 0.90100104 0.20331861),((V3 42.495594 (-53.756332) 36.63188,82.26547),V3 (-13.994319) (-6.1497493) 6.7633076,V3 (-3.1410325) 6.6301613 3.0234138e-2),((V3 58.644115 37.20186 58.620056,86.262726),V3 5.4610834 (-15.029127) 7.486924,V3 (-5.588184) (-3.6724644) (-3.101759)),((V3 (-22.410553) 10.888989 24.760492,52.37195),V3 3.5517094 10.775686 6.068233,V3 3.405976 1.4547812 (-0.44147408))]
t20 = fromList (Z :. 32) [((V3 70.64258 26.97726 70.65352,3.456227),V3 10.103177 (-11.083501) 10.430128,V3 (-0.25878596) (-0.1096651) (-0.14805585)),((V3 (-0.60530925) 31.649681 34.703568,63.459526),V3 11.983897 3.3875232 5.6731596,V3 1.9059213 (-2.2702324) (-0.38499674)),((V3 19.129223 67.63949 (-86.13814),74.34554),V3 12.898823 (-4.338295) (-6.4802012),V3 (-1.11779) (-2.3244681) 3.2478783),((V3 (-52.587482) (-0.21061647) (-36.487682),8.434827),V3 (-5.521948) 11.965574 (-6.018765),V3 0.5088869 0.27565396 0.25721252),((V3 27.600586 (-33.542427) 37.002804,16.776989),V3 (-5.2118816) (-8.994746) 7.3886538,V3 (-0.35461906) 1.1443055 0.33297035),((V3 74.98001 21.052492 68.71739,21.63172),V3 6.6536603 (-13.656725) 8.92714,V3 (-1.7712361) (-0.41551957) (-0.8035278)),((V3 (-0.1968162) 30.138866 32.549713,69.831604),V3 11.614001 3.864655 6.1276393,V3 1.9305562 (-2.0955043) 7.4945375e-2),((V3 13.495451 70.11945 (-91.47385),66.98223),V3 15.745442 (-1.9447142) (-6.1191072),V3 0.34707648 (-2.4542372) 3.844818),((V3 (-39.07626) 14.344181 (-24.048937),23.477612),V3 (-0.5911909) 12.481703 (-3.5879762),V3 1.2193754 0.2451571 0.5313611),((V3 20.755718 (-47.285156) 83.758934,4.5274367),V3 (-7.3864875) (-7.5831957) 12.738908,V3 1.0477281e-2 0.3141431 (-0.31150085)),((V3 29.731346 4.957616 67.74644,45.534313),V3 2.542373 (-5.4659686) 7.1639175,V3 (-0.773719) 0.55258787 (-2.949255)),((V3 3.2952871 40.414585 30.630938,37.293446),V3 12.0785885 1.6407151 5.635318,V3 0.5175421 (-2.311788) 0.13688904),((V3 17.204876 57.061028 (-92.11485),52.771004),V3 10.187838 1.4056993 (-7.992482),V3 (-0.5327076) 0.28180283 3.2848911),((V3 (-43.428978) 5.4403176 (-38.405262),83.92678),V3 1.3721125 17.93844 (-1.0416794),V3 4.1768746 2.3258047 2.9994802),((V3 25.61177 (-35.67625) 50.29802,13.032608),V3 (-5.5239754) (-8.40189) 8.819078,V3 (-0.17469631) 0.9371397 (-0.13386086)),((V3 77.91648 63.749935 111.700096,18.12446),V3 13.566664 (-10.48896) 12.8802395,V3 (-0.6257403) (-0.68909454) (-0.9268724)),((V3 8.015066 28.20771 52.363438,53.132633),V3 9.834624 (-0.42201662) 4.975245,V3 0.8522565 (-1.7886617) (-2.724254)),((V3 16.687307 65.11167 (-85.9828),94.62536),V3 13.431137 (-3.5456862) (-4.025685),V3 (-0.6603307) (-2.1941738) 4.275058),((V3 (-55.929226) (-7.5420556) (-37.130413),6.5728045),V3 (-7.2981763) 11.561206 (-6.1095667),V3 0.39473253 0.27254176 0.196624),((V3 17.732718 (-29.473835) 64.11756,53.180336),V3 (-6.2080007) (-1.0590713) 6.9066863,V3 0.49391943 3.4189227 (-2.5597522)),((V3 40.55933 11.31991 64.03876,91.3407),V3 1.478368e-2 (-10.987337) 2.5858128,V3 (-3.8935337) (-0.3199196) (-4.506024)),((V3 0.45339978 29.896873 39.454823,87.52959),V3 13.876055 2.7052927 3.5193348,V3 2.690946 (-2.7923274) (-1.7411938)),((V3 12.880193 55.68854 (-68.52059),75.542244),V3 12.610873 2.1888132 (-9.000532),V3 (-1.7048633e-2) (-0.18977338) 0.6773345),((V3 (-40.928196) 9.86234 (-41.4781),35.689384),V3 (-0.7128805) 12.819815 (-5.0434055),V3 1.6750612 0.72688335 1.3807626),((V3 20.569416 (-32.173176) 57.774376,77.35545),V3 (-9.122361) 0.8884996 5.742017,V3 1.2530923e-2 5.3429766 (-2.4258206)),((V3 82.24203 5.4715424 61.2392,34.4798),V3 1.3694282 (-15.498303) 7.885867,V3 (-3.0998273) 0.35917798 (-0.67349565)),((V3 4.1159596 18.343342 27.995344,20.805649),V3 5.547433 3.5543864 7.153706,V3 0.2545224 0.16027838 0.41772422),((V3 22.132597 68.11572 (-80.91648),58.3743),V3 12.430078 (-4.07933) (-8.919203),V3 (-1.4921408) (-1.9892223) 1.665496),((V3 (-53.46823) 4.8355 (-10.660793),20.659788),V3 (-3.3736873) 14.207917 (-1.6194743),V3 1.4933307 0.48024258 0.13877386),((V3 27.381256 (-56.825172) 43.436813,82.26547),V3 (-16.138443) 0.79542387 6.8798237,V3 (-1.272959) 7.1740904 0.16700138),((V3 61.48199 20.758127 64.70831,86.262726),V3 (-0.48431414) (-17.875822) 4.367215,V3 (-6.221025) (-2.0769675) (-3.1554008)),((V3 (-17.251387) 22.09256 30.678736,52.37195),V3 7.1905856 11.458972 5.7806373,V3 3.7821503 9.846892e-3 (-0.18520965))]
t30 = fromList (Z :. 32) [((V3 80.62529 15.850722 81.01362,3.456227),V3 9.832466 (-11.171636) 10.271142,V3 (-0.27626523) (-6.907271e-2) (-0.16648479)),((V3 12.109674 33.908443 40.254055,63.459526),V3 13.452332 0.7633101 5.4452367,V3 1.0651537 (-2.9039454) (-0.13198845)),((V3 31.485191 62.397385 (-91.180084),74.34554),V3 11.659424 (-6.17881) (-3.3099105),V3 (-1.3080394) (-1.4175643) 3.1050818),((V3 (-57.875084) 11.86496 (-42.392822),8.434827),V3 (-4.9964967) 12.19545 (-5.7677174),V3 0.53527856 0.19483553 0.24825694),((V3 22.266294 (-41.991844) 44.539543,16.776989),V3 (-5.4461217) (-7.745878) 7.7115583,V3 (-0.14457354) 1.3438723 0.30253243),((V3 80.82082 7.255052 77.26334,21.63172),V3 4.8354826 (-13.9168) 8.057859,V3 (-1.8398229) (-0.1291134) (-0.92295176)),((V3 12.16488 32.92552 38.752,69.831604),V3 13.12455 1.3194892 6.3205833,V3 1.1184452 (-2.9104452) 0.23775212),((V3 29.262188 67.1042 (-95.894775),66.98223),V3 15.635218 (-4.276028) (-2.3869843),V3 (-0.5043809) (-2.201609) 3.6215343),((V3 (-39.12235) 26.887955 (-27.421051),23.477612),V3 0.6162337 12.572925 (-3.130873),V3 1.1982962 (-1.6151225e-2) 0.4058443),((V3 13.381501 (-54.72822) 96.35743,4.5274367),V3 (-7.351956) (-7.273869) 12.427602,V3 5.11916e-2 0.3034085 (-0.3084455)),((V3 31.944645 (-0.24181631) 73.54906,45.534313),V3 1.8208045 (-4.8607187) 4.099617,V3 (-0.7120765) 0.6306646 (-3.160519)),((V3 15.529402 40.993393 36.353447,37.293446),V3 12.340105 (-0.740232) 5.8483925,V3 5.584805e-2 (-2.4297142) 0.2502288),((V3 27.210176 58.54192 (-98.62292),52.771004),V3 9.847976 1.4936708 (-4.6850176),V3 (-0.17808737) (-0.12827606) 3.3288074),((V3 (-40.165707) 24.159132 (-38.19885),83.92678),V3 5.569859 19.36941 1.6151043,V3 4.1652684 0.6796782 2.36701),((V3 20.0366 (-43.634075) 59.045513,13.032608),V3 (-5.610209) (-7.3880525) 8.644443,V3 (-2.1231862e-2) 1.0824242 (-0.2157843)),((V3 91.1954 52.98254 124.174416,18.12446),V3 12.923086 (-11.0728035) 11.991299,V3 (-0.65076464) (-0.49877062) (-0.85619026)),((V3 18.163801 26.950344 56.156433,53.132633),V3 10.439416 (-2.310497) 2.4027362,V3 0.35562944 (-1.9632834) (-2.4307075)),((V3 29.736702 60.715374 (-88.231476),94.62536),V3 12.49499 (-5.2733855) (-0.25494644),V3 (-1.143601) (-1.3175715) 3.3169105),((V3 (-63.04561) 4.129257 (-43.15318),6.5728045),V3 (-6.891207) 11.792309 (-5.9181933),V3 0.41236284 0.19797336 0.18787487),((V3 11.896064 (-29.014198) 69.856224,53.180336),V3 (-5.2224894) 2.284795 4.2921305,V3 1.3726617 3.257218 (-2.6621897)),((V3 38.84494 0.44165504 64.68979,91.3407),V3 (-3.7706373) (-10.44458) (-1.5761747),V3 (-3.6047552) 1.2989374 (-3.7820122)),((V3 15.253961 31.213158 42.37834,87.52959),V3 15.57238 (-0.5108675) 2.4073062,V3 0.77382207 (-3.5107894) (-0.5931102)),((V3 25.462185 57.7606 (-77.258286),75.542244),V3 12.529613 1.8682239 (-8.432913),V3 (-0.11828619) (-0.50076365) 0.56394),((V3 (-40.875896) 22.949284 (-45.92175),35.689384),V3 1.0001571 13.351651 (-3.730043),V3 1.7436737 0.38464665 1.2702756),((V3 11.7580805 (-28.916342) 62.435238,77.35545),V3 (-8.081674) 6.077168 3.352129,V3 1.9076473 4.964432 (-2.3579834)),((V3 82.2225 (-9.7786255) 68.797226,34.4798),V3 (-1.7052021) (-14.852521) 7.1237183,V3 (-3.0383008) 0.8755246 (-0.85059637)),((V3 9.812528 21.933826 35.338314,20.805649),V3 5.919625 3.5853083 7.5684195,V3 0.47318155 (-0.10099702) 0.39165217),((V3 33.87477 63.25305 (-89.045364),58.3743),V3 10.897609 (-5.691883) (-7.101499),V3 (-1.5258808) (-1.2934843) 1.9847765),((V3 (-56.17241) 19.20363 (-12.229358),20.659788),V3 (-1.8913364) 14.507622 (-1.5179769),V3 1.4663916 0.16752706 7.473919e-2),((V3 11.038544 (-52.75113) 50.393963,82.26547),V3 (-16.147457) 8.103466 7.0406375,V3 1.1229347 7.317746 0.116557844),((V3 58.12866 2.3073416 67.638176,86.262726),V3 (-6.899946) (-18.700304) 1.1591533,V3 (-6.4619718) 0.34747308 (-3.231288)),((V3 (-8.346832) 33.286644 36.39714,52.37195),V3 10.981637 10.563141 5.655627,V3 3.7102525 (-1.6548095) (-0.10352421))]
t40 = fromList (Z :. 32) [((V3 90.3346 4.655861 91.20859,3.456227),V3 9.561887 (-11.214318) 10.101466,V3 (-0.26128083) (-2.0770896e-2) (-0.16977718)),((V3 25.855879 33.27752 45.650112,63.459526),V3 13.874311 (-2.4134786) 5.3301144,V3 (-0.17173003) (-3.3428502) (-0.14888263)),((V3 42.55104 55.74881 (-93.12408),74.34554),V3 10.346969 (-7.033272) (-0.31666315),V3 (-1.2832952) (-0.39005303) 2.8811932),((V3 (-62.630367) 24.135597 (-48.04935),8.434827),V3 (-4.4623313) 12.3485365 (-5.5214076),V3 0.5272145 0.11860251 0.24403755),((V3 16.786787 (-49.09336) 52.37048,16.776989),V3 (-5.482549) (-6.270866) 7.9521694,V3 6.0247123e-2 1.5767819 0.17346881),((V3 84.83455 (-6.668477) 84.889885,21.63172),V3 3.0254977 (-13.872956) 7.0852513,V3 (-1.7604394) 0.1894979 (-1.002964)),((V3 25.607107 32.814 45.158234,69.831604),V3 13.595416 (-1.9758472) 6.462585,V3 (-0.13727047) (-3.549432) (-3.7056354e-3)),((V3 44.518757 61.90863 (-96.71034),66.98223),V3 14.625989 (-6.22489) 1.0272641,V3 (-1.417286) (-1.7000344) 3.2084227),((V3 (-37.96874) 39.424587 (-30.38036),23.477612),V3 1.8094404 12.464852 (-2.7568665),V3 1.1918833 (-0.17094232) 0.36163473),((V3 6.057052 (-61.869263) 108.64919,4.5274367),V3 (-7.286687) (-6.983825) 12.130093,V3 7.459494e-2 0.27627227 (-0.28570133)),((V3 33.423145 (-4.8133616) 76.19642,45.534313),V3 1.0209748 (-4.2072473) 0.8476473,V3 (-0.9101132) 0.69006634 (-3.3002555)),((V3 27.816963 39.14842 42.311176,37.293446),V3 12.133267 (-3.2016866) 6.077291,V3 (-0.43277112) (-2.4690394) 0.1829573),((V3 37.032055 59.871284 (-101.80806),52.771004),V3 9.842458 1.0014532 (-1.3576142),V3 0.113305725 (-0.80959976) 3.3034868),((V3 (-32.768158) 43.553585 (-35.62678),83.92678),V3 9.558228 19.116442 3.6231754,V3 3.785976 (-1.0030328) 1.7205341),((V3 14.439234 (-50.508904) 67.57433,13.032608),V3 (-5.5554476) (-6.2216606) 8.366025,V3 0.12124021 1.2241457 (-0.33175266)),((V3 103.82722 41.714848 135.79294,18.12446),V3 12.279673 (-11.474536) 11.176818,V3 (-0.631969) (-0.3265566) (-0.78048927)),((V3 28.635696 23.74509 57.530754,53.132633),V3 10.348517 (-4.291683) 0.19939163,V3 (-0.5118455) (-1.936669) (-1.9911488)),((V3 41.658382 55.011665 (-87.18198),94.62536),V3 11.169736 (-6.0489197) 2.4283314,V3 (-1.4343514) (-0.3365628) 2.1519272),((V3 (-69.752426) 15.998649 (-48.988125),6.5728045),V3 (-6.48451) 11.950421 (-5.7348514),V3 0.39747268 0.12604822 0.17903966),((V3 7.421006 (-25.314278) 72.93206,53.180336),V3 (-3.4275875) 5.3594904 1.5695516,V3 2.1104321 2.8862293 (-2.7693553)),((V3 33.593594 (-9.123072) 61.628304,91.3407),V3 (-6.853316) (-8.163884) (-4.585922),V3 (-2.5169895) 3.068793 (-2.2420175)),((V3 30.775204 29.06608 44.69013,87.52959),V3 14.991441 (-4.1634536) 2.3604884,V3 (-1.743295) (-3.6350572) 0.3263754),((V3 37.925953 59.291317 (-85.37278),75.542244),V3 12.364148 0.97157943 (-7.610811),V3 (-0.22051588) (-1.2753534) 1.148759),((V3 (-39.081818) 36.42463 (-49.090176),35.689384),V3 2.7722025 13.572521 (-2.4910996),V3 1.7876816 8.852193e-2 1.2181025),((V3 4.854909 (-20.765474) 64.73786,77.35545),V3 (-5.121062) 10.451305 1.0317328,V3 3.773904 3.7349844 (-2.2926235)),((V3 79.178535 (-24.155758) 75.49906,34.4798),V3 (-4.636625) (-13.707212) 6.141575,V3 (-2.8098998) 1.3618014 (-1.0914961)),((V3 15.977711 25.408234 43.059597,20.805649),V3 6.4937973 3.2579877 7.8726983,V3 0.63328594 (-0.5327105) 0.20720817),((V3 44.112415 57.10134 (-95.17267),58.3743),V3 9.473635 (-6.577284) (-4.840429),V3 (-1.3064284) (-0.55162036) 2.500792),((V3 (-57.413094) 33.74672 (-13.71971),20.659788),V3 (-0.45732188) 14.546219 (-1.4605455),V3 1.4030969 (-5.6085628e-2) 5.0729703e-2),((V3 (-4.132298) (-41.444485) 57.4354,82.26547),V3 (-13.4335) 15.047902 6.9562955,V3 4.059167 6.4290543 (-0.3307359)),((V3 48.41738 (-15.724357) 67.36842,86.262726),V3 (-12.948876) (-16.616163) (-1.95434),V3 (-5.4540496) 3.5695972 (-2.9190702)),((V3 4.210882 42.83211 41.997192,52.37195),V3 14.340451 8.013545 5.5130305,V3 2.9640288 (-3.234027) (-0.19869432))]
t50 = fromList (Z :. 32) [((V3 99.78429 (-6.5603447) 101.23478,3.456227),V3 9.319103 (-11.210923) 9.935835,V3 (-0.22626747) 2.1161372e-2 (-0.1612093)),((V3 39.403965 29.356451 50.871735,63.459526),V3 12.86763 (-5.723307) 5.028878,V3 (-1.6957306) (-3.1606607) (-0.4616191)),((V3 52.3492 48.69863 (-92.19782),74.34554),V3 9.166924 (-6.910074) 2.3809798,V3 (-1.0765165) 0.49746767 2.5362353),((V3 (-66.8613) 36.525005 (-53.462444),8.434827),V3 (-3.9560394) 12.425948 (-5.2827253),V3 0.48558196 4.514877e-2 0.23342745),((V3 11.3726 (-54.63127) 60.366547,16.776989),V3 (-5.284395) (-4.62866) 8.007034,V3 0.309564 1.6607597 (-5.4514244e-2)),((V3 87.09958 (-20.402815) 91.51911,21.63172),V3 1.3766433 (-13.507609) 6.0697675,V3 (-1.5429239) 0.502993 (-1.0176795)),((V3 38.87964 29.213264 51.52705,69.831604),V3 12.579766 (-5.5654917) 6.13499,V3 (-1.747105) (-3.477748) (-0.63458973)),((V3 58.371513 55.032394 (-94.33609),66.98223),V3 12.771849 (-7.537657) 3.9042752,V3 (-2.1691554) (-0.976144) 2.5849755),((V3 (-35.62298) 51.793858 (-32.97171),23.477612),V3 3.000215 12.232307 (-2.3830836),V3 1.1863849 (-0.2821353) 0.39073357),((V3 (-1.1938903) (-68.73547) 120.656364,4.5274367),V3 (-7.2055235) (-6.73064) 11.863677,V3 8.4682934e-2 0.2324943 (-0.24955781)),((V3 33.98479 (-8.668965) 75.568375,45.534313),V3 (-4.586573e-2) (-3.3565376) (-2.4003098),V3 (-1.161805) 1.0472943 (-3.1469493)),((V3 39.66494 34.850323 48.43695,37.293446),V3 11.395371 (-5.6083426) 6.138593,V3 (-0.99539036) (-2.3176267) (-6.147321e-2)),((V3 46.950523 60.39374 (-101.70575),52.771004),V3 10.027083 (-0.18237326) 1.846281,V3 0.21004155 (-1.4657336) 3.093771),((V3 (-21.612383) 61.96557 (-31.32596),83.92678),V3 12.976039 17.290213 5.0295744,V3 3.0800977 (-2.4412982) 1.1717454),((V3 8.96526 (-56.172928) 75.77116,13.032608),V3 (-5.345359) (-4.985807) 7.967873,V3 0.27868465 1.2160217 (-0.45238936)),((V3 115.829254 30.117777 146.63062,18.12446),V3 11.671261 (-11.721733) 10.436247,V3 (-0.5865162) (-0.18780562) (-0.70882756)),((V3 38.582184 18.651218 56.93042,53.132633),V3 9.270124 (-5.9622445) (-1.4593434),V3 (-1.5178046) (-1.3589051) (-1.3558631)),((V3 52.169697 48.95184 (-83.96839),94.62536),V3 9.706987 (-5.938324) 3.989206,V3 (-1.4470835) 0.41542193 1.1349429),((V3 (-76.06361) 27.99487 (-54.644337),6.5728045),V3 (-6.106245) 12.040813 (-5.5623775),V3 0.36062056 6.338345e-2 0.1667967),((V3 5.031253 (-18.753942) 73.24428,53.180336),V3 (-1.0452096) 7.9019423 (-1.2293646),V3 2.5434313 2.215863 (-2.8002636)),((V3 25.895203 (-15.654797) 56.379826,91.3407),V3 (-8.374308) (-4.2960773) (-5.6613545),V3 (-0.61054236) 4.410234 (-0.105147086)),((V3 44.56931 23.377563 47.275223,87.52959),V3 11.912463 (-7.3660054) 2.9104905,V3 (-4.0473733) (-2.6802368) 0.6384738),((V3 50.153812 59.54019 (-92.28699),75.542244),V3 12.008861 (-0.7881906) (-5.8424706),V3 (-0.4955644) (-2.1168833) 2.3230572),((V3 (-35.506397) 49.987667 (-51.03989),35.689384),V3 4.5507164 13.495833 (-1.2958468),V3 1.7571652 (-0.21390966) 1.1755395),((V3 1.6586281 (-8.966029) 64.74854,77.35545),V3 (-0.6585472) 13.033994 (-1.2206159),V3 4.837213 1.534798 (-2.2026932)),((V3 73.34591 (-37.17399) 81.11334,34.4798),V3 (-7.204541) (-12.09446) 4.9343133,V3 (-2.3330922) 1.8091398 (-1.2886307)),((V3 22.757414 28.347914 50.975887,20.805649),V3 7.116842 2.4678946 7.908502,V3 0.5789135 (-0.98542297) (-0.11901239)),((V3 53.056896 50.391014 (-98.801895),58.3743),V3 8.367776 (-6.7536325) (-2.0602012),V3 (-0.93099135) 0.10514579 2.9887574),((V3 (-57.253033) 48.23814 (-15.15559),20.659788),V3 0.8975221 14.393842 (-1.4017532),V3 1.3112133 (-0.22530983) 7.0312925e-2),((V3 (-15.272543) (-23.845793) 64.09268,82.26547),V3 (-7.877729) 20.243881 6.091751,V3 6.59736 3.9433155 (-1.3863378)),((V3 33.405663 (-30.212833) 64.24376,86.262726),V3 (-17.00329) (-11.36592) (-4.358442),V3 (-2.6607215) 6.4482036 (-1.8884766)),((V3 19.681992 49.188995 47.388447,52.37195),V3 16.6021 4.146414 5.202059,V3 1.6236293 (-4.2790256) (-0.41353542))]

