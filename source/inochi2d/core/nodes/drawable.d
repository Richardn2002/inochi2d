/*
    Inochi2D Drawable base class

    Copyright © 2020, Inochi2D Project
    Distributed under the 2-Clause BSD License, see LICENSE file.
    
    Authors: Luna Nielsen
*/
module inochi2d.core.nodes.drawable;
public import inochi2d.core.nodes.defstack;
import inochi2d.integration;
import inochi2d.fmt.serialize;
import inochi2d.math;
import bindbc.opengl;
import std.exception;
import inochi2d.core;
import std.string;

private GLuint drawableVAO;

package(inochi2d) {
    bool doGenerateBounds = false;
}

/**
    Sets whether Inochi2D should keep track of the bounds
*/
void inSetUpdateBounds(bool state) {
    doGenerateBounds = state;
}

/**
    Nodes that are meant to render something in to the Inochi2D scene
    Other nodes don't have to render anything and serve mostly other 
    purposes.

    The main types of Drawables are Parts and Masks
*/

@TypeId("Drawable")
abstract class Drawable : Node {
private:

    void updateIndices() {
        
    }

    void updateVertices() {


        // Zero-fill the deformation delta
        this.deformation.length = vertices.length;
        foreach(i; 0..deformation.length) {
            this.deformation[i] = vec2(0, 0);
        }
        this.updateDeform();
    }

    void updateDeform() {
        // Important check since the user can change this every frame
        enforce(
            deformation.length == vertices.length, 
            "Data length mismatch for %s, deformation length=%d whereas vertices.length=%d, if you want to change the mesh you need to change its data with Part.rebuffer.".format(name, deformation.length, vertices.length)
        );
        postProcess();

        this.updateBounds();
    }

protected:
    /**
        The mesh data of this part

        NOTE: DO NOT MODIFY!
        The data in here is only to be used for reference.
    */
    MeshData data;

    /**
        Allows serializing self data (with pretty serializer)
    */
    override
    void serializeSelfImpl(ref InochiSerializer serializer, bool recursive=true) {
        super.serializeSelfImpl(serializer, recursive);
        serializer.putKey("mesh");
        serializer.serializeValue(data);
    }

    override
    SerdeException deserializeFromFghj(Fghj data) {
        import std.stdio : writeln;
        super.deserializeFromFghj(data);
        if (auto exc = data["mesh"].deserializeValue(this.data)) return exc;

        this.vertices = this.data.vertices.dup;

        // Update indices and vertices
        this.updateIndices();
        this.updateVertices();
        return null;
    }

    void onDeformPushed(ref Deformation deform) { }

    override
    void preProcess() {
        if (preProcessed)
            return;
        preProcessed = true;
        if (preProcessFilter !is null) {
            overrideTransformMatrix = null;
            mat4 matrix = this.transform.matrix;
            auto filterResult = preProcessFilter(vertices, deformation, &matrix);
            if (filterResult[0] !is null) {
                deformation = filterResult[0];
            } 
            if (filterResult[1] !is null) {
                overrideTransformMatrix = new MatrixHolder(*filterResult[1]);
            }
        }
    }

    override
    void postProcess() {
        if (postProcessed)
            return;
        postProcessed = true;
        if (postProcessFilter !is null) {
            overrideTransformMatrix = null;
            mat4 matrix = this.transform.matrix;
            auto filterResult = postProcessFilter(vertices, deformation, &matrix);
            if (filterResult[0] !is null) {
                deformation = filterResult[0];
            } 
            if (filterResult[1] !is null) {
                overrideTransformMatrix = new MatrixHolder(*filterResult[1]);
            }
        }
    }

package(inochi2d):
    final void notifyDeformPushed(ref Deformation deform) {
        onDeformPushed(deform);
    }

public:

    abstract void renderMask(bool dodge = false);

    /**
        Constructs a new drawable surface
    */
    this(Node parent = null) {
        super(parent);

        // Create deformation stack
        this.deformStack = DeformationStack(this);
    }

    /**
        Constructs a new drawable surface
    */
    this(MeshData data, Node parent = null) {
        this(data, inCreateUID(), parent);
    }

    /**
        Constructs a new drawable surface
    */
    this(MeshData data, uint uid, Node parent = null) {
        super(uid, parent);
        this.data = data;
        this.deformStack = DeformationStack(this);

        // Set the deformable points to their initial position
        this.vertices = data.vertices.dup;

        // Update indices and vertices
        this.updateIndices();
        this.updateVertices();
    }

    ref vec2[] vertices() {
        return data.vertices;
    }

    /**
        Deformation offset to apply
    */
    vec2[] deformation;

    /**
        The bounds of this drawable
    */
    vec4 bounds;

    /**
        Deformation stack
    */
    DeformationStack deformStack;

    /**
        Refreshes the drawable, updating its vertices
    */
    final void refresh() {
        this.updateVertices();
    }
    
    /**
        Refreshes the drawable, updating its deformation deltas
    */
    final void refreshDeform() {
        this.updateDeform();
    }

    override
    void beginUpdate() {
        deformStack.preUpdate();
        super.beginUpdate();
    }

    /**
        Updates the drawable
    */
    override
    void update() {
        preProcess();
        deformStack.update();
        super.update();
        this.updateDeform();
    }

    /**
        Draws the drawable
    */
    override
    void drawOne() {
        super.drawOne();
    }

    /**
        Draws the drawable without any processing
    */
    void drawOneDirect(bool forMasking) { }

    override
    string typeId() { return "Drawable"; }

    /**
        Updates the drawable's bounds
    */
    void updateBounds() {
        if (!doGenerateBounds) return;

        // Calculate bounds
        Transform wtransform = transform;
        bounds = vec4(wtransform.translation.xyxy);
        mat4 matrix = getDynamicMatrix();
        foreach(i, vertex; vertices) {
            vec2 vertOriented = vec2(matrix * vec4(vertex+deformation[i], 0, 1));
            if (vertOriented.x < bounds.x) bounds.x = vertOriented.x;
            if (vertOriented.y < bounds.y) bounds.y = vertOriented.y;
            if (vertOriented.x > bounds.z) bounds.z = vertOriented.x;
            if (vertOriented.y > bounds.w) bounds.w = vertOriented.y;
        }
    }

    /**
        Returns the mesh data for this Part.
    */
    final ref MeshData getMesh() {
        return this.data;
    }

    /**
        Changes this mesh's data
    */
    void rebuffer(ref MeshData data) {
        this.data = data;
        this.updateIndices();
        this.updateVertices();
    }
    
    /**
        Resets the vertices of this drawable
    */
    final void reset() {
        vertices[] = data.vertices;
    }
}

/**
    Begins a mask

    This causes the next draw calls until inBeginMaskContent/inBeginDodgeContent or inEndMask 
    to be written to the current mask.

    This also clears whatever old mask there was.
*/
void inBeginMask(bool hasMasks) {
    inRenderSubmit(IN_MASK_BEGIN, null);
}

/**
    End masking

    Once masking is ended content will no longer be masked by the defined mask.
*/
void inEndMask() {
    inRenderSubmit(IN_MASK_END, null);
}

/**
    Starts masking content

    NOTE: This have to be run within a inBeginMask and inEndMask block!
*/
void inBeginMaskContent() {
    inRenderSubmit(IN_MASK_ELEM, null);
}
