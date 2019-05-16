//
//  ViewController.swift
//  k4
//
//  Created by sk on 2019/5/15.
//  Copyright © 2019 sk. All rights reserved.
//

import Cocoa
import PromiseKit
import Alamofire
import Ji
typealias Path = String
let K4 = "http://pic.netbian.com"
enum SaveKind{
    case thubnail
    case big
}
//请自行在 顶级目录下创建 big thubnail 目录
let picPath = "/Users/sk/Desktop/pics"

extension SaveKind{
    var dirName: String{
        switch self {
        case .thubnail:
            return "thubnail"
        case .big:
            return "big"
        }
    }
    var filePath: String{
        return [picPath , self.dirName].joined(separator: "/")
    }
}
class ViewController: NSViewController {
    
    override func viewDidLoad() {
        super.viewDidLoad()
        // Do any additional setup after loading the view.
        var urls = ["4kfengjing","4kmeinv","4kyouxi","4kdongman","4kyingshi","4kmingxing","4kqiche","4kdongwu","4krenwu","4kmeishi","4kzongjiao","4kbeijing","shoujibizhi"].map({ (item:String) -> String in
            return [K4, item].joined(separator: "/")
        }).makeIterator()
        
        let generator =     AnyIterator<Promise<Void>>.init { () -> Promise<Void>? in
            guard let url  = urls.next() else {
                return nil
            }
          return  firstly{
                after(seconds: 10)
                }.then({ _ in
                    return self.fetch(page: url)
                })
        }
        when(fulfilled: generator, concurrently: 2)
            .ensure {
                print("完成结束")
                
            }.catch { (e:Error) in
                print(e)
        }
        
    }
    
    override var representedObject: Any? {
        didSet {
            // Update the view, if already loaded.
        }
    }
    func fetch( page: String = "http://pic.netbian.com/shoujibizhi/index.html") ->Promise<Void>{
        var nextUrl = page
        
        return  firstly{
            Alamofire.request(page).responseString()
            }.then { (pro:(string: String, response: PMKAlamofireDataResponse)) -> Promise<Ji> in
                return   Promise{ seal in
                    let ji = Ji.init(htmlString: pro.string)
                    if ji != nil{
                        seal.fulfill(ji!)
                    }else{
                        seal.reject(JiError.initError)
                    }
                }
            }.then { (ji:Ji) -> Promise<([String],[String],String,Bool)> in
                
                let values =   ji.xPath("//*[@id='main']/div[3]/ul/li/a/img")!.map({ (node:JiNode) -> String in
                    return  K4 + (node.attributes["src"] ?? "")
                })
                
                let nextPage = ji.xPath("//div[@class='page']/b")?.first!
                let nextPageNode =  nextPage!.nextSibling
                var isLastPage = false
                if nextPageNode == nil {
                    print("结束")
                    isLastPage = true
                }
                if  nextPageNode != nil{
                    if  nextPageNode!.tag! != "a" {
                        //结束
                    }else{
                        print(nextPageNode!.attributes)
                        nextUrl              =  K4 + nextPageNode!.attributes["href"]!
                    }
                }
                //每个缩略图对应的详情url
                let pageDetail =   ji.xPath("//div[@class='slist']/ul/li/a")?.map({ (node:JiNode) -> String in
                    return K4 + node.attributes["href"]!
                })
                
                return   Promise<([String],[String],String,Bool)>.value((pageDetail ?? [], values, nextUrl , isLastPage))
                
            }.then({ (value:(pageDetail:[String], thubnails:[String], nextUrl:String, isLastPage:Bool)) -> Promise<Void> in
                // 确保本页 和 对应的详情图片爬取完成之后开始下一个首页
                return  when(resolved: self.big(details: value.pageDetail).done({ (localPics:[String]) in
                    print("高清图片完成：\(localPics)")
                }).ensure {
                    
                    },self.save(pics: value.thubnails).ensure {
                        
                }).asVoid().done({ _ in
                    if value.isLastPage == false{
                        after(.seconds(10)).done({ _ in                      
                            self.fetch(page: nextUrl)
                        })
                    }
                })
            })
        
    }
    func big(  details:[String])->Promise<[String]>{
        var pages =  details.makeIterator()
        let generator  =  AnyIterator<Promise<String>>.init { () -> Promise<String>? in
            guard let page = pages.next() else {
                return nil
            }
            return Alamofire.request(page)
                .responseString().then({ (value:(string: String, response: PMKAlamofireDataResponse)) -> Promise<String> in
                    let ji = Ji.init(htmlString: value.string)
                    let imgs =   ji!.xPath( "//div[@class='photo-pic']/a/img")
                    if imgs?.isEmpty ?? false {

                        return   Promise<String>{ seal in
                        seal.reject(JiError.nodesNotFound)
                        }
                        
                    }else{
                    let img = K4 + imgs!.first!.attributes["src"]!
                    
                    return self.save(img: img, to: SaveKind.big)
                    }
                })
        }
        return when(fulfilled: generator, concurrently: 2)
    }
    func save( pics:[String], saveKind:SaveKind = SaveKind.thubnail)->Promise<Void>{
        var urls =    pics.makeIterator()
        
        let generator =  AnyIterator<Promise<String>>.init({ () -> Promise<String>? in
            guard  let url = urls.next() else{
                return nil
            }
            return self.save(img: url)
        })
        return when(fulfilled: generator, concurrently: 2).done({ (filePaths:[String]) in
            //            self.fetch(page: nextUrl)
        })
    }
    func save( img:String, to saveKind:SaveKind = SaveKind.thubnail)->Promise<String>{
        return  Alamofire.request(img)
            .responseData().then({ (imgData:(data: Data, response: PMKAlamofireDataResponse)) -> Promise<String> in
                
                return   Promise{ seal in
                    do{
                        let path  = [saveKind.filePath , imgData.response.request!.url!.pathComponents.last!].joined(separator: "/")
                        
                        try imgData.data.write(to: URL.init(fileURLWithPath:path ))
                        seal.fulfill(path)
                    }catch{
                        seal.reject(error)
                    }
                }
            })
    }
    
}
extension Ji{
    func promiseNode(for path:String) ->Promise<[String]>{
        return  Promise<[JiNode]>{ seal in
            let tmp = self;
            
            let nodes = tmp.xPath(path)
            
            if nodes != nil {
                seal.fulfill(nodes!)
            }else{
                seal.reject(JiError.nodesNotFound)
            }
            }.thenMap({ (node:JiNode) -> Promise<String> in
                return Promise.value(node.attributes["src"]!)
            })
    }
    
}


enum JiError: Error {
    case initError
    case nodesNotFound
}
