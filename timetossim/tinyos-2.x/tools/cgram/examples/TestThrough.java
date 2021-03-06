/*
* Copyright (c) 2007 #### RWTH Aachen Universtiy ####.
* All rights reserved.
*
* Redistribution and use in source and binary forms, with or without
* modification, are permitted provided that the following conditions
* are met:
* - Redistributions of source code must retain the above copyright
*   notice, this list of conditions and the following disclaimer.
* - Redistributions in binary form must reproduce the above copyright
*   notice, this list of conditions and the following disclaimer in the
*   documentation and/or other materials provided with the
*   distribution.
* - Neither the name of #### RWTH Aachen University ####  nor the names of
*   its contributors may be used to endorse or promote products derived
*   from this software without specific prior written permission.
*
* THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS
* ``AS IS'' AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT
* LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS
* FOR A PARTICULAR PURPOSE ARE DISCLAIMED.  IN NO EVENT SHALL STANFORD
* UNIVERSITY OR ITS CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT,
* INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES
* (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR
* SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION)
* HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT,
* STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE)
* ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED
* OF THE POSSIBILITY OF SUCH DAMAGE.
*
* @author Muhammad Hamad Alizai <hamad.alizai@rwth-aachen.de>
*/



import java.io.*;

import antlr.*;

import antlr.debug.misc.*;
import antlr.collections.*;

public class TestThrough
{
    public static void main(String[] args)
    {
        for (int i=0; i<args.length; i++)
        {
        try
            {
	   
            String programName = args[i];
	    String str;
            String originalSource = "";
            DataInputStream dis = null;
	    String en = System.getenv("HOME");
	    String s = en + "/tinyos-2.x-contrib/timetossim/tinyos-2.x/tools/cgram/examples/check_time3.c";
	    BufferedReader reader = new BufferedReader(new FileReader(s));
	    //System.out.println("typedef long long int sim_time_t;"); 
	    System.out.println("inline int check_time(long long int avr_time);");
	    
            if (programName.equals("-")) {
                dis = new DataInputStream( System.in );
            }   
            else {
                dis = new DataInputStream(new FileInputStream(programName));
            }
            GnuCLexer lexer =
                new GnuCLexer ( dis );
            lexer.setTokenObjectClass("CToken");
            lexer.initialize();
            // Parse the input expression.
            GnuCParser parser = new GnuCParser ( lexer );
            
            // set AST node type to TNode or get nasty cast class errors
            parser.setASTNodeType(TNode.class.getName());
            TNode.setTokenVocabulary("GNUCTokenTypes");

            // invoke parser
            try {
                parser.translationUnit();
            }
            catch (RecognitionException e) {
                System.err.println("Fatal IO error:\n"+e);
                System.exit(1);
            }
            catch (TokenStreamException e) {
                System.err.println("Fatal IO error:\n"+e);
                System.exit(1);
            }
	/*
	    	TNode superNode = new TNode();
		AST ast = parser.getAST();
        	superNode.addChild(((TNode)ast).deepCopyWithRightSiblings());
        
        	ASTFrame inputFrame = new ASTFrame("hello", superNode);
        	inputFrame.setVisible(true);
	*/
            // Garbage collection hint
            System.gc();

//          System.out.println("AST:" + parser.getAST());
//          TNode.printTree(parser.getAST());
    
            // run through the treeParser, doesn't do anything 
            // but verify that the grammar is ok
            GnuCTreeParser treeParser = new GnuCTreeParser();
            
            // set AST node type to TNode or get nasty cast class errors
            treeParser.setASTNodeType(TNode.class.getName());

            // walk that tree (it doesn't build a new tree -- 
            // it would just be a copy if it did)
            treeParser.translationUnit( parser.getAST() );

//          System.out.println(treeParser.getAST().toStringList());
            // Garbage collection hint
            System.gc();

            GnuCEmitter e = new GnuCEmitter(lexer.getPreprocessorInfoChannel());
			e.asmP = new AsmParser("build/micaz/asm.txt");
			e.asmP.parse();
            // set AST node type to TNode or get nasty cast class errors
            e.setASTNodeType(TNode.class.getName());

            // walk that tree
			
			AST ast = parser.getAST();
			((TNode)ast).doubleLink();
			e.translationUnit( ast );
            //e.translationUnit( parser.getAST() );

            // Garbage collection hint
	    while((str = reader.readLine()) != null)
	    {
		System.out.println(str);
            }
            System.gc();
		
            }
        catch ( Exception e )
            {
            System.err.println ( "exception: " + e);
            e.printStackTrace();
            }
        }
	
    }
}

        

