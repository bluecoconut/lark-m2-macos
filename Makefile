.PHONY: app release clean

app:
	./scripts/build.sh

release: app
	cd build && ditto -c -k --sequesterRsrc --keepParent "Lark M2 Status.app" "Lark-M2-Status.zip"

clean:
	rm -rf build
